using System.ComponentModel;
using System.Runtime.InteropServices;

namespace MrrpInjector.Native;

/// <summary>
/// Thin P/Invoke wrappers over the handful of Win32 calls a classic
/// LoadLibrary injector needs. Nothing exotic in here — these are the same
/// documented kernel32 entry points every open-source injector uses.
/// </summary>
internal static class NativeMethods
{
    // ---- Access rights -----------------------------------------------------

    [Flags]
    public enum ProcessAccess : uint
    {
        CreateThread = 0x0002,
        QueryInformation = 0x0400,
        VmOperation = 0x0008,
        VmWrite = 0x0020,
        VmRead = 0x0010,

        /// <summary>Everything the inject path touches, OR'd together.</summary>
        InjectRights =
            CreateThread | QueryInformation | VmOperation | VmWrite | VmRead,
    }

    [Flags]
    public enum AllocationType : uint
    {
        Commit = 0x1000,
        Reserve = 0x2000,
    }

    [Flags]
    public enum MemoryProtection : uint
    {
        ReadWrite = 0x04,
    }

    [Flags]
    public enum FreeType : uint
    {
        Release = 0x8000,
    }

    // ---- kernel32 ----------------------------------------------------------

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(
        ProcessAccess desiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
        int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr VirtualAllocEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        uint dwSize,
        AllocationType flAllocationType,
        MemoryProtection flProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool VirtualFreeEx(
        IntPtr hProcess,
        IntPtr lpAddress,
        uint dwSize,
        FreeType dwFreeType);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WriteProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        uint nSize,
        out UIntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateRemoteThread(
        IntPtr hProcess,
        IntPtr lpThreadAttributes,
        uint dwStackSize,
        IntPtr lpStartAddress,
        IntPtr lpParameter,
        uint dwCreationFlags,
        out IntPtr lpThreadId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr GetModuleHandle(string moduleName);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetExitCodeThread(IntPtr hThread, out uint lpExitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWow64Process(IntPtr hProcess, out bool wow64Process);

    public const uint Infinite = 0xFFFFFFFF;
    public const uint WaitObject0 = 0x0;

    /// <summary>
    /// Builds a <see cref="Win32Exception"/> from the current thread's last
    /// error so callers can surface a real "why" instead of a bare boolean.
    /// </summary>
    public static Win32Exception LastError() => new(Marshal.GetLastWin32Error());
}
