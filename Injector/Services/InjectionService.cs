using System.Diagnostics;
using System.IO;
using System.Text;
using FsocietyInjector.Native;

namespace FsocietyInjector.Services;

/// <summary>The outcome of an inject attempt, ready to print to the log.</summary>
public readonly record struct InjectionResult(bool Success, string Message)
{
    public static InjectionResult Ok(string message) => new(true, message);
    public static InjectionResult Fail(string message) => new(false, message);
}

/// <summary>
/// Classic remote-thread LoadLibrary injection.
///
/// The recipe (the one every documented injector uses):
///   1. Open a handle to the target with the rights we need.
///   2. Allocate a page in the target and write the full DLL path into it.
///   3. Resolve kernel32!LoadLibraryA — its address is identical across
///      processes of the same bitness, so ours doubles as the target's.
///   4. CreateRemoteThread(target, LoadLibraryA, pathPage) so the target
///      loads the DLL on its own thread.
///   5. Wait, read the thread's exit code (the loaded module handle), clean up.
/// </summary>
public static class InjectionService
{
    /// <summary>Validates the request, then runs the inject off the UI thread.</summary>
    public static Task<InjectionResult> InjectAsync(int processId, string dllPath)
        => Task.Run(() => Inject(processId, dllPath));

    public static InjectionResult Inject(int processId, string dllPath)
    {
        // ---- Pre-flight checks so failures are legible, not cryptic --------

        if (string.IsNullOrWhiteSpace(dllPath))
            return InjectionResult.Fail("No DLL selected.");

        if (!File.Exists(dllPath))
            return InjectionResult.Fail($"DLL not found on disk:\n{dllPath}");

        var fullPath = Path.GetFullPath(dllPath);

        Process target;
        try
        {
            target = Process.GetProcessById(processId);
        }
        catch
        {
            return InjectionResult.Fail($"Target process {processId} is no longer running.");
        }

        IntPtr hProcess = IntPtr.Zero;
        IntPtr remoteMem = IntPtr.Zero;
        IntPtr hThread = IntPtr.Zero;

        try
        {
            // 1) Open the target.
            hProcess = NativeMethods.OpenProcess(
                NativeMethods.ProcessAccess.InjectRights, false, processId);
            if (hProcess == IntPtr.Zero)
                return InjectionResult.Fail(
                    $"OpenProcess failed — {NativeMethods.LastError().Message} " +
                    "(try running the injector as administrator).");

            // Path is written as a null-terminated ANSI string for LoadLibraryA.
            var pathBytes = Encoding.ASCII.GetBytes(fullPath + "\0");
            var size = (uint)pathBytes.Length;

            // 2) Allocate + write the path.
            remoteMem = NativeMethods.VirtualAllocEx(
                hProcess, IntPtr.Zero, size,
                NativeMethods.AllocationType.Commit | NativeMethods.AllocationType.Reserve,
                NativeMethods.MemoryProtection.ReadWrite);
            if (remoteMem == IntPtr.Zero)
                return InjectionResult.Fail(
                    $"VirtualAllocEx failed — {NativeMethods.LastError().Message}.");

            if (!NativeMethods.WriteProcessMemory(hProcess, remoteMem, pathBytes, size, out var written)
                || written.ToUInt32() != size)
                return InjectionResult.Fail(
                    $"WriteProcessMemory failed — {NativeMethods.LastError().Message}.");

            // 3) Resolve LoadLibraryA.
            var kernel32 = NativeMethods.GetModuleHandle("kernel32.dll");
            if (kernel32 == IntPtr.Zero)
                return InjectionResult.Fail("Could not locate kernel32.dll.");

            var loadLibrary = NativeMethods.GetProcAddress(kernel32, "LoadLibraryA");
            if (loadLibrary == IntPtr.Zero)
                return InjectionResult.Fail("Could not resolve LoadLibraryA.");

            // 4) Fire the remote thread.
            hThread = NativeMethods.CreateRemoteThread(
                hProcess, IntPtr.Zero, 0, loadLibrary, remoteMem, 0, out _);
            if (hThread == IntPtr.Zero)
                return InjectionResult.Fail(
                    $"CreateRemoteThread failed — {NativeMethods.LastError().Message}.");

            // 5) Wait for LoadLibrary to return.
            var wait = NativeMethods.WaitForSingleObject(hThread, 10_000);
            if (wait != NativeMethods.WaitObject0)
                return InjectionResult.Fail(
                    "The DLL's entry point did not return within 10s. " +
                    "It may still be loading, or DllMain may be blocking.");

            NativeMethods.GetExitCodeThread(hThread, out var exitCode);

            // On x64 the module handle is 64-bit and gets truncated in the
            // thread exit code, so a zero here is the only reliable failure tell.
            if (exitCode == 0)
                return InjectionResult.Fail(
                    "LoadLibrary returned NULL — the DLL failed to load in the " +
                    "target (wrong architecture, missing dependency, or blocked).");

            return InjectionResult.Ok(
                $"Injected {Path.GetFileName(fullPath)} into {target.ProcessName} ({processId}).");
        }
        catch (Exception ex)
        {
            return InjectionResult.Fail($"Unexpected error: {ex.Message}");
        }
        finally
        {
            // Free the remote path page; leave the DLL mapped (that's the point).
            if (remoteMem != IntPtr.Zero && hProcess != IntPtr.Zero)
                NativeMethods.VirtualFreeEx(
                    hProcess, remoteMem, 0, NativeMethods.FreeType.Release);

            if (hThread != IntPtr.Zero) NativeMethods.CloseHandle(hThread);
            if (hProcess != IntPtr.Zero) NativeMethods.CloseHandle(hProcess);
            target.Dispose();
        }
    }
}
