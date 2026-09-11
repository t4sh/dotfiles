# Windows shortcut identity is stored separately from WScript.Shell properties.
# PKEY_AppUserModel_ID: https://learn.microsoft.com/windows/win32/properties/props-system-appusermodel-id
if (-not ('Dotfiles.ShortcutIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Dotfiles {
    public static class ShortcutIdentity {
        [StructLayout(LayoutKind.Sequential)]
        struct PropertyKey { public Guid Format; public uint Id; }
        [StructLayout(LayoutKind.Explicit, Size=24)]
        struct PropVariant {
            [FieldOffset(0)] public ushort Type;
            [FieldOffset(8)] public IntPtr Value;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPropertyStore {
            void GetCount(out uint count);
            void GetAt(uint index, out PropertyKey key);
            void GetValue(ref PropertyKey key, out PropVariant value);
            void SetValue(ref PropertyKey key, ref PropVariant value);
            void Commit();
        }
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=true)]
        static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr context, uint flags,
            ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant value);
        [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
        static extern void SHChangeNotify(uint change, uint flags, string path, string otherPath);
        public static void Notify(string path) {
            SHChangeNotify(0x00002000, 0x1005, path, null); // UPDATEITEM, PATHW | FLUSH
        }
        public static void NotifyMove(string path, string destination) {
            SHChangeNotify(0x00000001, 0x1005, path, destination); // RENAMEITEM
        }
        static PropertyKey AppIdKey() {
            return new PropertyKey { Format=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id=5 };
        }
        static IPropertyStore Open(string path, bool write) {
            var iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, write ? 2u : 0u, ref iid, out store));
            return store;
        }
        public static string Get(string path) {
            var store = Open(path, false);
            var key = AppIdKey();
            var value = new PropVariant();
            try {
                store.GetValue(ref key, out value);
                if (value.Type == 0) return "";
                if (value.Type != 31) throw new InvalidOperationException("Unexpected shortcut AppUserModelID type");
                return Marshal.PtrToStringUni(value.Value) ?? "";
            } finally { PropVariantClear(ref value); Marshal.ReleaseComObject(store); }
        }
        public static void Set(string path, string appId) {
            var store = Open(path, true);
            var key = AppIdKey();
            var value = new PropVariant { Type=31, Value=Marshal.StringToCoTaskMemUni(appId) };
            try { store.SetValue(ref key, ref value); store.Commit(); }
            finally { PropVariantClear(ref value); Marshal.ReleaseComObject(store); }
        }
    }
}
'@
}
