#if UNITY_EDITOR

using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
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

        public static void SwitchToRequestBuildTarget()
        {
            int exitCode = ExecuteSwitchToRequestBuildTarget();
            EditorApplication.Exit(exitCode);
        }

        public static void PrepareBuildSequence()
        {
            int exitCode = ExecutePrepareBuildSequence();
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

            if (!BuildSettingBridge.EnsureAvailable(false))
            {
                Debug.LogError("[CIBuildEntry] Build Setting package is required. Install/update Build Automation through ActionFit Package Manager so catalog dependencies are written to Packages/manifest.json, or manually add the Build Setting Git UPM URL before running CI.");
                return 1;
            }

            ScriptableObject settings = BuildSettingBridge.FindSettingsAsset();
            if (settings == null)
            {
                Debug.LogError("[CIBuildEntry] BuildSettingsSO not found");
                return 1;
            }

            if (!ApplyRequest(settings, request))
                return 1;

            BuildSettingBridge.ApplyVersionSettings(settings);
            ApplyPlayerIdentifiers(settings);

            if (!ValidatePreparedBuildSymbols(request))
                return 1;

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

        internal static bool ApplyRequest(ScriptableObject settings, BuildRequest request)
        {
            string androidAlias = request.androidKeyaliasName?.Trim();
            string androidPackageName = request.androidPackageName?.Trim();
            string iosBundleId = request.iosBundleId?.Trim();
            string iosDevelopmentTeamId = Environment.GetEnvironmentVariable("IOS_DEVELOPMENT_TEAM_ID")?.Trim();

            if (!string.IsNullOrEmpty(request.buildVersion)) BuildSettingBridge.SetString(settings, "buildVersion", request.buildVersion);
            if (!string.IsNullOrEmpty(request.bundleNo)) BuildSettingBridge.SetString(settings, "bundleNo", request.bundleNo);
            if (!string.IsNullOrEmpty(request.buildFileName)) BuildSettingBridge.SetString(settings, "buildFileName", request.buildFileName);
            if (!string.IsNullOrEmpty(androidPackageName)) BuildSettingBridge.SetString(settings, "androidPackageName", androidPackageName);
            if (!string.IsNullOrEmpty(iosBundleId)) BuildSettingBridge.SetString(settings, "iosPackageName", iosBundleId);
            if (!string.IsNullOrEmpty(iosDevelopmentTeamId)) BuildSettingBridge.SetString(settings, "developmentTeamId", iosDevelopmentTeamId);
            if (!string.IsNullOrEmpty(androidAlias)) BuildSettingBridge.SetString(settings, "keyStoreAlias", androidAlias);
            if (!BuildSettingBridge.SetBool(settings, "developmentBuild", request.developmentBuild))
            {
                Debug.LogError(
                    $"[CIBuildEntry] BuildSettingsSO does not support developmentBuild. " +
                    $"Update {BuildSettingBridge.PackageId} to {BuildSettingBridge.MinimumVersion} or newer.");
                return false;
            }

            BuildSettingBridge.SetBool(settings, "saveFileInProject", true);
            BuildSettingBridge.SetBool(settings, "manageSymbolsOnBuild", request.autoConfigureBuildSymbols);

            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CIBuildEntry] Request applied: trigger={request.triggerSource}, unityProjectPath={request.unityProjectPath}, platform={request.platform}, kind={request.buildKind}, upload={request.uploadTarget}, profile={request.distributionProfile}, autoConfigureBuildSymbols={request.autoConfigureBuildSymbols}, developmentBuild={request.developmentBuild}, androidPackage={androidPackageName}, iosBundle={iosBundleId}, iosTeamId={iosDevelopmentTeamId}, androidAlias={androidAlias}");
            return true;
        }

        private static void ApplyPlayerIdentifiers(ScriptableObject settings)
        {
            string androidPackageName = BuildSettingBridge.GetString(settings, "androidPackageName");
            string iosPackageName = BuildSettingBridge.GetString(settings, "iosPackageName");

            if (!string.IsNullOrWhiteSpace(androidPackageName))
                PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, androidPackageName.Trim());

            if (!string.IsNullOrWhiteSpace(iosPackageName))
                PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.iOS, iosPackageName.Trim());
        }

        private static BuildReport RunBuild(ScriptableObject settings, BuildRequest request)
        {
            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            Debug.Log(
                $"[CIBuildEntry] request platform={request.platform}, resolvedPlatform={platform}, " +
                $"activeBuildTarget={EditorUserBuildSettings.activeBuildTarget}, " +
                $"selectedGroup={EditorUserBuildSettings.selectedBuildTargetGroup}");

            switch (platform)
            {
                case BuildRequestPlatform.Android:
#if UNITY_ANDROID
                    ApplyAndroidSigning(request);
                    bool aab = request.buildKind != BuildRequestKind.AndroidApk;
                    return BuildSettingBridge.BuildAndroidForCI(settings, aab);
#else
                    Debug.LogError("[CIBuildEntry] Android build requested, but UNITY_ANDROID is not active. Run SwitchToRequestBuildTarget in a separate Unity batchmode step before BuildFromRequest.");
                    return null;
#endif
                case BuildRequestPlatform.iOS:
#if UNITY_IOS
                    return BuildSettingBridge.BuildIosForCI(settings);
#else
                    Debug.LogError("[CIBuildEntry] iOS build requested, but UNITY_IOS is not active. Run SwitchToRequestBuildTarget in a separate Unity batchmode step before BuildFromRequest.");
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

        private static int ExecuteSwitchToRequestBuildTarget()
        {
            BuildRequest request = BuildRequestUtility.Load();
            if (request == null) return 1;

            if (request.triggerSource != BuildRequest.BuildCommitTriggerSource)
            {
                Debug.LogError($"[CIBuildEntry] Unsupported trigger source: {request.triggerSource}");
                return 1;
            }

            return PrepareBuildTarget(request);
        }

        private static int ExecutePrepareBuildSequence()
        {
            BuildRequest request = BuildRequestUtility.Load();
            if (request == null) return 1;

            if (request.triggerSource != BuildRequest.BuildCommitTriggerSource)
            {
                Debug.LogError($"[CIBuildEntry] Unsupported trigger source: {request.triggerSource}");
                return 1;
            }

            if (!TryResolveBuildSequence(
                    request.platform,
                    EditorUserBuildSettings.activeBuildTarget,
                    out BuildRequestPlatform first,
                    out BuildRequestPlatform second))
            {
                Debug.LogError($"[CIBuildEntry] Unsupported build sequence platform: {request.platform}");
                return 1;
            }

            if (!BuildRequestUtility.TrySaveWorkingRequest(
                    request,
                    first,
                    out BuildRequest firstRequest,
                    out string firstRequestPath,
                    out string firstRequestError))
            {
                Debug.LogError($"[CIBuildEntry] {firstRequestError}");
                return 1;
            }

            BuildRequest secondRequest = null;
            string secondRequestPath = "";
            if (second != BuildRequestPlatform.None &&
                !BuildRequestUtility.TrySaveWorkingRequest(
                    request,
                    second,
                    out secondRequest,
                    out secondRequestPath,
                    out string secondRequestError))
            {
                Debug.LogError($"[CIBuildEntry] {secondRequestError}");
                return 1;
            }

            if (PrepareBuildTarget(firstRequest) != 0)
                return 1;

            string androidRequestPath = first == BuildRequestPlatform.Android
                ? firstRequestPath
                : second == BuildRequestPlatform.Android ? secondRequestPath : "";
            string iosRequestPath = first == BuildRequestPlatform.iOS
                ? firstRequestPath
                : second == BuildRequestPlatform.iOS ? secondRequestPath : "";
            BuildRequest androidRequest = first == BuildRequestPlatform.Android
                ? firstRequest
                : second == BuildRequestPlatform.Android ? secondRequest : null;
            BuildRequest iosRequest = first == BuildRequestPlatform.iOS
                ? firstRequest
                : second == BuildRequestPlatform.iOS ? secondRequest : null;

            string outputPath = Environment.GetEnvironmentVariable("BUILD_SEQUENCE_OUTPUT_PATH")?.Trim();
            if (string.IsNullOrEmpty(outputPath))
            {
                Debug.LogError("[CIBuildEntry] BUILD_SEQUENCE_OUTPUT_PATH is required");
                return 1;
            }

            File.AppendAllLines(
                outputPath,
                new[]
                {
                    $"first={first}",
                    $"second={(second == BuildRequestPlatform.None ? "" : second.ToString())}",
                    $"android_request_path={androidRequestPath}",
                    $"ios_request_path={iosRequestPath}",
                    $"android_upload_target={androidRequest?.uploadTarget.ToString() ?? ""}",
                    $"android_bundle_no={androidRequest?.bundleNo ?? ""}",
                    $"android_development_build={FormatBooleanOutput(androidRequest?.developmentBuild)}",
                    $"ios_upload_target={iosRequest?.uploadTarget.ToString() ?? ""}",
                    $"ios_bundle_no={iosRequest?.bundleNo ?? ""}",
                    $"ios_development_build={FormatBooleanOutput(iosRequest?.developmentBuild)}"
                });

            Debug.Log(
                $"[CIBuildEntry] Build sequence prepared: request={request.platform}, " +
                $"active={EditorUserBuildSettings.activeBuildTarget}, first={first}, second={second}");
            return 0;
        }

        private static string FormatBooleanOutput(bool? value)
        {
            return value.HasValue ? value.Value.ToString().ToLowerInvariant() : "";
        }

        internal static bool TryResolveBuildSequence(
            BuildRequestPlatform requestedPlatform,
            BuildTarget activeBuildTarget,
            out BuildRequestPlatform first,
            out BuildRequestPlatform second)
        {
            first = BuildRequestPlatform.None;
            second = BuildRequestPlatform.None;

            switch (requestedPlatform)
            {
                case BuildRequestPlatform.Current:
                    first = activeBuildTarget switch
                    {
                        BuildTarget.Android => BuildRequestPlatform.Android,
                        BuildTarget.iOS => BuildRequestPlatform.iOS,
                        _ => BuildRequestPlatform.None
                    };
                    return first != BuildRequestPlatform.None;
                case BuildRequestPlatform.Android:
                case BuildRequestPlatform.iOS:
                    first = requestedPlatform;
                    return true;
                case BuildRequestPlatform.Both:
                    if (activeBuildTarget == BuildTarget.iOS)
                    {
                        first = BuildRequestPlatform.iOS;
                        second = BuildRequestPlatform.Android;
                    }
                    else
                    {
                        first = BuildRequestPlatform.Android;
                        second = BuildRequestPlatform.iOS;
                    }

                    return true;
                default:
                    return false;
            }
        }

        private static int PrepareBuildTarget(BuildRequest request)
        {
            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            if (!TryGetBuildTarget(platform, out BuildTargetGroup group, out BuildTarget target))
            {
                Debug.LogError($"[CIBuildEntry] Unsupported target switch platform: {platform}");
                return 1;
            }

            Debug.Log(
                $"[CIBuildEntry] target switch requested: requestPlatform={request.platform}, " +
                $"resolvedPlatform={platform}, target={target}, group={group}, " +
                $"activeBuildTarget={EditorUserBuildSettings.activeBuildTarget}, " +
                $"selectedGroup={EditorUserBuildSettings.selectedBuildTargetGroup}");

            if (request.autoConfigureBuildSymbols &&
                !CustomSymbolsBridge.TryApplyBuildSymbols(target, out string symbolError))
            {
                Debug.LogError($"[CIBuildEntry] {symbolError}");
                return 1;
            }

            if (EditorUserBuildSettings.activeBuildTarget == target)
            {
                Debug.Log($"[CIBuildEntry] Active build target is already {target}");
                return 0;
            }

            bool switched = EditorUserBuildSettings.SwitchActiveBuildTarget(group, target);
            if (!switched)
            {
                Debug.LogError($"[CIBuildEntry] Failed to switch active build target to {target}");
                return 1;
            }

            if (request.autoConfigureBuildSymbols &&
                !CustomSymbolsBridge.TryApplyBuildSymbols(target, out string postSwitchSymbolError))
            {
                Debug.LogError($"[CIBuildEntry] {postSwitchSymbolError}");
                return 1;
            }

            Debug.Log($"[CIBuildEntry] Switched active build target to {target}");
            return 0;
        }

        private static bool ValidatePreparedBuildSymbols(BuildRequest request)
        {
            if (!request.autoConfigureBuildSymbols)
            {
                Debug.Log("[CIBuildEntry] Automatic build symbol setup is disabled for this request");
                return true;
            }

            BuildRequestPlatform platform = ResolvePlatform(request.platform);
            if (!TryGetBuildTarget(platform, out _, out BuildTarget target))
            {
                Debug.LogError($"[CIBuildEntry] Cannot validate Custom Symbols for platform: {platform}");
                return false;
            }

            if (!CustomSymbolsBridge.TryValidateBuildSymbols(target, out string error))
            {
                Debug.LogError($"[CIBuildEntry] {error}");
                return false;
            }

            return true;
        }

        private static bool TryGetBuildTarget(BuildRequestPlatform platform, out BuildTargetGroup group, out BuildTarget target)
        {
            switch (platform)
            {
                case BuildRequestPlatform.Android:
                    group = BuildTargetGroup.Android;
                    target = BuildTarget.Android;
                    return true;
                case BuildRequestPlatform.iOS:
                    group = BuildTargetGroup.iOS;
                    target = BuildTarget.iOS;
                    return true;
                default:
                    group = default;
                    target = default;
                    return false;
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
        private static void ApplyAndroidSigning(BuildRequest request)
        {
            string keystorePath = ResolveAndroidKeystorePath(request);
            string keystorePass = PickRequestOrEnvironment(request.androidKeystorePassword, "ANDROID_KEYSTORE_PASS");
            string keyaliasPass = PickRequestOrEnvironment(request.androidAliasPassword, "ANDROID_KEYALIAS_PASS");
            string aliasName = request.androidKeyaliasName?.Trim();
            bool hasAliasName = !string.IsNullOrEmpty(aliasName);

            if (string.IsNullOrEmpty(keystorePath) && !hasAliasName && string.IsNullOrEmpty(keystorePass) && string.IsNullOrEmpty(keyaliasPass))
            {
                Debug.Log("[CIBuildEntry] No request or runner keystore values found; using project signing settings as-is");
                return;
            }

            PlayerSettings.Android.useCustomKeystore = true;
            if (!string.IsNullOrEmpty(keystorePath))
            {
                if (!File.Exists(keystorePath))
                    throw new FileNotFoundException("[CIBuildEntry] Android keystore file not found", keystorePath);

                PlayerSettings.Android.keystoreName = keystorePath;
            }
            if (hasAliasName) PlayerSettings.Android.keyaliasName = aliasName;
            if (!string.IsNullOrEmpty(keystorePass)) PlayerSettings.Android.keystorePass = keystorePass;
            if (!string.IsNullOrEmpty(keyaliasPass)) PlayerSettings.Android.keyaliasPass = keyaliasPass;

            Debug.Log($"[CIBuildEntry] Android signing applied: requestKeystore={!string.IsNullOrEmpty(request.androidKeystoreBase64)}, alias={PlayerSettings.Android.keyaliasName}, requestKeystorePassword={!string.IsNullOrEmpty(request.androidKeystorePassword)}, requestAliasPassword={!string.IsNullOrEmpty(request.androidAliasPassword)}");
        }
#endif

        private static string ResolveAndroidKeystorePath(BuildRequest request)
        {
            string requestKeystoreBase64 = request.androidKeystoreBase64?.Trim();
            if (!string.IsNullOrEmpty(requestKeystoreBase64))
                return WriteRequestKeystore(request);

            return Environment.GetEnvironmentVariable("ANDROID_KEYSTORE_PATH")?.Trim();
        }

        private static string WriteRequestKeystore(BuildRequest request)
        {
            string fileName = SanitizeFileName(request.androidKeystoreFileName, "android-request.keystore");
            string directory = Path.Combine(BuildRequestUtility.UnityProjectRoot, ".build", "ci-keystore");
            string path = Path.Combine(directory, fileName);

            try
            {
                Directory.CreateDirectory(directory);
                byte[] bytes = Convert.FromBase64String(request.androidKeystoreBase64);
                File.WriteAllBytes(path, bytes);
                Debug.Log($"[CIBuildEntry] Android keystore restored from BuildCommit request: {path}");
                return path;
            }
            catch (Exception exception)
            {
                throw new InvalidOperationException(
                    "[CIBuildEntry] Failed to restore Android keystore from BuildCommit request",
                    exception);
            }
        }

        private static string SanitizeFileName(string value, string fallback)
        {
            string fileName = Path.GetFileName(value?.Trim());
            if (string.IsNullOrEmpty(fileName)) fileName = fallback;

            foreach (char invalidCharacter in Path.GetInvalidFileNameChars())
                fileName = fileName.Replace(invalidCharacter, '_');

            return string.IsNullOrEmpty(fileName) ? fallback : fileName;
        }

        private static string PickRequestOrEnvironment(string requestValue, string environmentVariableName)
        {
            string normalizedRequestValue = requestValue?.Trim();
            if (!string.IsNullOrEmpty(normalizedRequestValue)) return normalizedRequestValue;

            return Environment.GetEnvironmentVariable(environmentVariableName)?.Trim();
        }
    }
}

#endif
