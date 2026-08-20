using System.Runtime.InteropServices;
using System.Text.Json;

namespace Gaji.Windows;

internal static class NativeCore
{
    private static readonly JsonSerializerOptions JsonOptions = new() {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_inspect_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_execute_json([MarshalAs(UnmanagedType.LPUTF8Str)] string request);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_commit_graph_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path, nuint limit);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_blame_json(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string file);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_worktrees_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_submodules_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_stashes_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint gaji_file_hunks_json(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string file,
        [MarshalAs(UnmanagedType.I1)] bool staged);

    [DllImport("gaji_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern void gaji_string_free(nint value);

    public static CoreSnapshot Inspect(string path) => Decode<CoreSnapshot>(gaji_inspect_json(path));
    public static CoreGraphCommit[] Graph(string path, nuint limit = 500) =>
        Decode<CoreGraphCommit[]>(gaji_commit_graph_json(path, limit));
    public static CoreBlameLine[] Blame(string path, string file) =>
        Decode<CoreBlameLine[]>(gaji_blame_json(path, file));
    public static CoreWorktree[] Worktrees(string path) => Decode<CoreWorktree[]>(gaji_worktrees_json(path));
    public static CoreSubmodule[] Submodules(string path) => Decode<CoreSubmodule[]>(gaji_submodules_json(path));
    public static CoreStash[] Stashes(string path) => Decode<CoreStash[]>(gaji_stashes_json(path));
    public static CoreDiffHunk[] Hunks(string path, string file, bool staged) =>
        Decode<CoreDiffHunk[]>(gaji_file_hunks_json(path, file, staged));

    public static void Execute(object request)
    {
        var json = JsonSerializer.Serialize(request, JsonOptions);
        var envelope = DecodeEnvelope<JsonElement>(gaji_execute_json(json));
        if (!envelope.Ok) throw new InvalidOperationException(envelope.Error ?? "Git operation failed");
    }

    private static T Decode<T>(nint pointer)
    {
        var envelope = DecodeEnvelope<T>(pointer);
        if (!envelope.Ok || envelope.Value is null)
            throw new InvalidOperationException(envelope.Error ?? "Native core failed");
        return envelope.Value;
    }

    private static CoreEnvelope<T> DecodeEnvelope<T>(nint pointer)
    {
        if (pointer == 0) throw new InvalidOperationException("Native core returned no response");
        try
        {
            var json = Marshal.PtrToStringUTF8(pointer) ?? throw new InvalidOperationException("Invalid native response");
            return JsonSerializer.Deserialize<CoreEnvelope<T>>(json, JsonOptions)
                ?? throw new InvalidOperationException("Could not decode native response");
        }
        finally { gaji_string_free(pointer); }
    }
}

internal sealed record CoreEnvelope<T>(bool Ok, T? Value, string? Error);
internal sealed record CoreSnapshot(string Root, string Branch, CoreChange[] Changes, CoreCommit[] RecentCommits);
internal sealed record CoreChange(string IndexStatus, string WorktreeStatus, string Path);
internal sealed record CoreCommit(string Id, string Author, string AuthoredAt, string Subject);
internal sealed record CoreGraphCommit(
    string Id, string[] Parents, string[] References, string Author, string AuthoredAt, string Subject);
internal sealed record CoreBlameLine(int LineNumber, string Commit, string Author, long AuthoredAt, string Content);
internal sealed record CoreWorktree(string Path, string Commit, string? Branch, bool IsBare);
internal sealed record CoreSubmodule(string Path, string Commit, char State);
internal sealed record CoreStash(int Index, string Reference, string Subject);
internal sealed record CoreDiffHunk(int Id, string Header, string Patch);
