using System.Runtime.InteropServices;
using System.Text.Json;

namespace Rift.Windows;

internal static class NativeCore
{
    private static readonly JsonSerializerOptions JsonOptions = new() {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_inspect_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_execute_json([MarshalAs(UnmanagedType.LPUTF8Str)] string request);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_commit_graph_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path, nuint limit);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern void rift_string_free(nint value);

    public static CoreSnapshot Inspect(string path) => Decode<CoreSnapshot>(rift_inspect_json(path));
    public static CoreGraphCommit[] Graph(string path, nuint limit = 500) =>
        Decode<CoreGraphCommit[]>(rift_commit_graph_json(path, limit));

    public static void Execute(object request)
    {
        var json = JsonSerializer.Serialize(request, JsonOptions);
        var envelope = DecodeEnvelope<JsonElement>(rift_execute_json(json));
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
        finally { rift_string_free(pointer); }
    }
}

internal sealed record CoreEnvelope<T>(bool Ok, T? Value, string? Error);
internal sealed record CoreSnapshot(string Root, string Branch, CoreChange[] Changes, CoreCommit[] RecentCommits);
internal sealed record CoreChange(string IndexStatus, string WorktreeStatus, string Path);
internal sealed record CoreCommit(string Id, string Author, string AuthoredAt, string Subject);
internal sealed record CoreGraphCommit(
    string Id, string[] Parents, string[] References, string Author, string AuthoredAt, string Subject);
