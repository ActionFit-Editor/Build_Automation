#if UNITY_EDITOR

using System;
using ActionFit.BuildSetting.Editor;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor
{
    public static class CIBuildEntry
    {
        public static void BuildFromRequest()
        {
            int exitCode = ExecuteBuildFromRequest();
            EditorApplication.Exit(exitCode);
        }

        private static int ExecuteBuildFromRequest()
        {
            BuildRequest request = BuildRequestUtility.Load();
            if (request == null) return 1;

            if (request.triggerSource != BuildRequest.BuildCommitTriggerSource)
            {
                Debug.LogError($"[CIBuildEntry] Unsupported trigger source: {request.triggerSource}");
                return 1;
            }

            BuildSettingsSO settings = BuildSettingsSO.FindSettingsAsset();
            if (settings == null)
            {
                Debug.LogError("[CIBuildEntry] BuildSettingsSO not found");
                return 1;
            }

            ApplyRequest(settings, request);
            BuildSettingsApplier.ApplyVersionSettings(settings);

            BuildReport report = RunBuild(settings, request);
            if (report == null)
            {
                Debug.LogError("[CIBuildEntry] Build report is null");
                return 1;
            }

            BuildSummary summary = report.summary;
            Debug.Log($"[CIBuildEntry] Build result: {summary.result}, output={summary.outputPath}");
            return summary.result == BuildResult.Succeeded ? 0 : 1;
        }

        private static void ApplyRequest(BuildSettingsSO settings, BuildRequest request)
        {
            if (!string.IsNullOrEmpty(request.buildVersion)) settings.buildVersion = request.buildVersion;
            if (!string.IsNullOrEmpty(request.bundleNo)) settings.bundleNo = request.bundleNo;
            if (!string.IsNullOrEmpty(request.buildFileName)) settings.buildFileName = request.buildFileName;
            settings.saveFileInProject = true;

            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CIBuildEntry] Request applied: trigger={request.triggerSource}, platform={request.platform}, kind={request.buildKind}, upload={request.uploadTarget}");
        }

        private static BuildReport RunBuild(BuildSettingsSO settings, BuildRequest request)
        {
            BuildRequestPlatform platform = ResolvePlatform(request.platform);

            switch (platform)
            {
                case BuildRequestPlatform.Android:
#if UNITY_ANDROID
                    ApplyAndroidSigning();
                    bool aab = request.buildKind != BuildRequestKind.AndroidApk;
                    return AOSBuildProcess.BuildForCI(settings, aab);
#else
                    Debug.LogError("[CIBuildEntry] Android build requested, but UNITY_ANDROID is not active");
                    return null;
#endif
                case BuildRequestPlatform.iOS:
#if UNITY_IOS
                    return iOSBuildProcess.BuildForCI(settings);
#else
                    Debug.LogError("[CIBuildEntry] iOS build requested, but UNITY_IOS is not active");
                    return null;
#endif
                case BuildRequestPlatform.Both:
                    Debug.LogError("[CIBuildEntry] Both platform requests must be split by the workflow");
                    return null;
                default:
                    Debug.LogError($"[CIBuildEntry] Unsupported platform: {platform}");
                    return null;
            }
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

#if UNITY_ANDROID
        // CI 환경변수로 전달된 keystore 비밀번호를 PlayerSettings에 주입한다.
        // keystore 파일/alias 이름은 프로젝트 설정에 이미 저장되어 있으므로 비밀번호만 채운다.
        // 환경변수가 없으면(로컬 빌드) 프로젝트에 저장된 서명 설정을 그대로 사용한다.
        private static void ApplyAndroidSigning()
        {
            string keystorePass = Environment.GetEnvironmentVariable("ANDROID_KEYSTORE_PASS");
            string keyaliasPass = Environment.GetEnvironmentVariable("ANDROID_KEYALIAS_PASS");

            if (string.IsNullOrEmpty(keystorePass) && string.IsNullOrEmpty(keyaliasPass))
            {
                Debug.Log("[CIBuildEntry] No keystore env vars found; using project signing settings as-is");
                return;
            }

            PlayerSettings.Android.useCustomKeystore = true;
            if (!string.IsNullOrEmpty(keystorePass)) PlayerSettings.Android.keystorePass = keystorePass;
            if (!string.IsNullOrEmpty(keyaliasPass)) PlayerSettings.Android.keyaliasPass = keyaliasPass;

            Debug.Log("[CIBuildEntry] Android keystore passwords injected from environment");
        }
#endif
    }
}

#endif
