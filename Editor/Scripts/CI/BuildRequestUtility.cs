#if UNITY_EDITOR

using System;
using System.IO;
using ActionFit.BuildSetting.Editor;
using UnityEditor;
using UnityEngine;
using Process = System.Diagnostics.Process;
using ProcessStartInfo = System.Diagnostics.ProcessStartInfo;

namespace ActionFit.BuildAutomation.Editor
{
    public static class BuildRequestUtility
    {
        public const string RelativePath = ".build/build_request.json";

        public static string AbsolutePath => Path.GetFullPath(Path.Combine(ProjectRoot, RelativePath));

        private static string ProjectRoot => Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

        public static BuildRequest Create(
            BuildSettingsSO settings,
            BuildRequestPlatform platform,
            BuildRequestKind buildKind,
            BuildRequestUploadTarget uploadTarget)
        {
            if (settings == null)
            {
                Debug.LogError("[BuildRequestUtility] BuildSettingsSO is null");
                return null;
            }

            BuildRequestPlatform resolvedPlatform = ResolvePlatform(platform);

            return new BuildRequest
            {
                triggerSource = BuildRequest.BuildCommitTriggerSource,
                platform = resolvedPlatform,
                buildKind = buildKind,
                uploadTarget = uploadTarget,
                buildVersion = settings.buildVersion,
                bundleNo = settings.bundleNo,
                buildFileName = settings.buildFileName,
                sourceBranch = RunGitCommand("rev-parse --abbrev-ref HEAD"),
                sourceCommit = RunGitCommand("rev-parse HEAD"),
                createdAtUtc = DateTime.UtcNow.ToString("o")
            };
        }

        public static bool Save(BuildRequest request)
        {
            if (request == null)
            {
                Debug.LogError("[BuildRequestUtility] BuildRequest is null");
                return false;
            }

            string directory = Path.GetDirectoryName(AbsolutePath);
            if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);

            File.WriteAllText(AbsolutePath, JsonUtility.ToJson(request, true));
            AssetDatabase.Refresh();
            Debug.Log($"[BuildRequestUtility] BuildRequest saved: {RelativePath}");
            return true;
        }

        public static BuildRequest Load()
        {
            if (!File.Exists(AbsolutePath))
            {
                Debug.LogError($"[BuildRequestUtility] BuildRequest not found: {RelativePath}");
                return null;
            }

            string json = File.ReadAllText(AbsolutePath);
            BuildRequest request = JsonUtility.FromJson<BuildRequest>(json);
            if (request == null)
            {
                Debug.LogError($"[BuildRequestUtility] Failed to parse BuildRequest: {RelativePath}");
                return null;
            }

            return request;
        }

        private static BuildRequestPlatform ResolvePlatform(BuildRequestPlatform platform)
        {
            if (platform != BuildRequestPlatform.Current) return platform;

            return EditorUserBuildSettings.activeBuildTarget switch
            {
                BuildTarget.Android => BuildRequestPlatform.Android,
                BuildTarget.iOS => BuildRequestPlatform.iOS,
                _ => BuildRequestPlatform.Current
            };
        }

        private static string RunGitCommand(string args)
        {
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = args,
                    WorkingDirectory = ProjectRoot,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using (var process = Process.Start(startInfo))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    return process.ExitCode == 0 ? output.Trim() : "";
                }
            }
            catch (Exception e)
            {
                Debug.LogError($"[BuildRequestUtility] git {args} failed: {e.Message}");
                return "";
            }
        }
    }
}

#endif
