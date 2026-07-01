#if UNITY_EDITOR

using System.Collections.Generic;
using System.IO;
using System.Text;
using ActionFit.BuildSetting.Editor;
using UnityEditor;
using UnityEngine;
using Process = System.Diagnostics.Process;
using ProcessStartInfo = System.Diagnostics.ProcessStartInfo;

namespace ActionFit.BuildAutomation.Editor
{
    public class BuildCommitWindow : EditorWindow
    {
        #region Fields

        private const string SOPrefsKey = BuildSettingsSO.SOPrefsKey; // BuildSettingsWindow와 동일한 키 공유
        private const string DistributionProfilePrefsKey = "BuildCommitDistributionProfile";
        private const string BuildTagPrefix = "build";

        private BuildSettingsSO _settings; // 빌드 설정 SO
        private SerializedObject _serializedSettings; // SO 직렬화 래퍼
        private BuildRequestPlatform _requestPlatform = BuildRequestPlatform.None; // 원격 빌드 플랫폼
        private BuildRequestKind _requestKind = BuildRequestKind.Default; // 원격 빌드 종류
        private BuildRequestUploadTarget _uploadTarget = BuildRequestUploadTarget.None; // 업로드 대상
        private BuildRequestDistributionProfile _distributionProfile = BuildRequestDistributionProfile.Actionfit; // 배포 계정 프로필

        private Vector2 _logScrollPosition; // 로그 스크롤 위치
        private readonly List<string> _logs = new(); // 실행 결과 로그 목록

        #endregion

        #region Window

        [MenuItem("Tools/ActionFit/BuildSetting/AutoBuild", false, 21)]
        public static void ShowWindow()
        {
            var window = GetWindow<BuildCommitWindow>("AutoBuild");
            window.minSize = new Vector2(360, 320);
            window.Show();
        }

        private void OnEnable()
        {
            LoadSO();
            ApplyDefaultRequestOptionsForPlatform(ResolvePlatform(_requestPlatform));
        }

        #endregion

        #region GUI

        private void OnGUI()
        {
            EditorGUILayout.Space(8);
            DrawSOField();
            EditorGUILayout.Space(8);

            if (_settings == null)
                LoadSO();

            if (_settings == null)
            {
                EditorGUILayout.HelpBox("BuildSettingsSO를 연결해주세요.", MessageType.Warning);
                return;
            }

            _serializedSettings?.Update();

            DrawVersionInput();
            EditorGUILayout.Space(10);
            DrawBuildRequestOptions();
            EditorGUILayout.Space(10);
            DrawWorkflowSync();
            EditorGUILayout.Space(10);
            DrawButtons();
            EditorGUILayout.Space(8);
            DrawLog();

            ApplySerializedIfModified();
        }

        #endregion

        #region Draw Methods

        // SO ObjectField 표시
        private void DrawSOField()
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.PrefixLabel("Build Settings");

            EditorGUI.BeginChangeCheck();
            _settings = (BuildSettingsSO)EditorGUILayout.ObjectField(_settings, typeof(BuildSettingsSO), false);
            if (EditorGUI.EndChangeCheck())
            {
                if (_settings != null)
                {
                    _serializedSettings = new SerializedObject(_settings);
                    EditorPrefs.SetString(SOPrefsKey, AssetDatabase.GetAssetPath(_settings));
                }
                else
                {
                    _serializedSettings = null;
                }
            }

            EditorGUILayout.EndHorizontal();
        }

        // 버전 / 번들ID 입력 및 저장 커밋 메시지 미리보기
        private void DrawVersionInput()
        {
            EditorGUILayout.LabelField("Version Info", EditorStyles.boldLabel);

            var versionProp = _serializedSettings.FindProperty("buildVersion");
            var bundleProp = _serializedSettings.FindProperty("bundleNo");

            EditorGUILayout.PropertyField(versionProp, new GUIContent("Version"));
            EditorGUILayout.PropertyField(bundleProp, new GUIContent("Bundle ID"));

            EditorGUILayout.Space(5);

            string preview = CreateCommitMessage(versionProp.stringValue, bundleProp.stringValue);
            EditorGUILayout.LabelField("Storage Commit Preview:", EditorStyles.miniLabel);
            GUI.enabled = false;
            EditorGUILayout.TextField(preview);
            GUI.enabled = true;
        }

        // 원격 CI 빌드 요청 옵션 표시
        private void DrawBuildRequestOptions()
        {
            EditorGUILayout.LabelField("CI Build Request", EditorStyles.boldLabel);

            EditorGUI.BeginChangeCheck();
            _requestPlatform = (BuildRequestPlatform)EditorGUILayout.EnumPopup("Platform", _requestPlatform);
            if (EditorGUI.EndChangeCheck())
                ApplyDefaultRequestOptionsForPlatform(ResolvePlatform(_requestPlatform));

            using (new EditorGUI.DisabledScope(!CanCreateBuildCommitRequest()))
            {
                _requestKind = (BuildRequestKind)EditorGUILayout.EnumPopup("Build Kind", _requestKind);
                _uploadTarget = (BuildRequestUploadTarget)EditorGUILayout.EnumPopup("Upload Target", _uploadTarget);
            }

            EditorGUI.BeginChangeCheck();
            _distributionProfile = (BuildRequestDistributionProfile)EditorGUILayout.EnumPopup("Distribution Profile", _distributionProfile);
            if (EditorGUI.EndChangeCheck())
                EditorPrefs.SetInt(DistributionProfilePrefsKey, (int)_distributionProfile);

            string version = _serializedSettings.FindProperty("buildVersion").stringValue;
            string bundleNo = _serializedSettings.FindProperty("bundleNo").stringValue;
            string tagPreview = CreateBuildTag(version, bundleNo, "commit");
            EditorGUILayout.LabelField("Build Tag Preview:", EditorStyles.miniLabel);
            GUI.enabled = false;
            EditorGUILayout.TextField(tagPreview);
            GUI.enabled = true;

            BuildRequestPlatform resolvedPlatform = ResolvePlatform(_requestPlatform);
            if (!CanCreateBuildCommitRequest())
            {
                EditorGUILayout.HelpBox(
                    "Platform을 선택해야 BuildCommit request를 커밋할 수 있습니다.",
                    MessageType.Warning);
            }

            if (resolvedPlatform == BuildRequestPlatform.Android || resolvedPlatform == BuildRequestPlatform.Both)
            {
                string androidAlias = BuildRequestUtility.GetAndroidKeyaliasName(_settings);
                EditorGUILayout.LabelField("Android Alias:", EditorStyles.miniLabel);
                GUI.enabled = false;
                EditorGUILayout.TextField(string.IsNullOrEmpty(androidAlias) ? "Project Default" : androidAlias);
                GUI.enabled = true;
            }

            DrawLocalRunnerSecretNotice(resolvedPlatform);

            EditorGUILayout.HelpBox(
                $"{BuildRequestUtility.RelativePath} will be committed as storage. GitHub Actions will build when the build tag is pushed.",
                MessageType.Info);
        }

        private void DrawWorkflowSync()
        {
            EditorGUILayout.LabelField("GitHub Workflow", EditorStyles.boldLabel);

            bool isCurrent = BuildCommitWorkflowSyncUtility.IsWorkflowCurrent();
            EditorGUILayout.HelpBox(
                BuildCommitWorkflowSyncUtility.GetStatusMessage(),
                isCurrent ? MessageType.Info : MessageType.Warning);

            if (GUILayout.Button("Update GitHub Workflow", GUILayout.Height(26)))
            {
                UpdateWorkflowFile();
            }
        }

        private void DrawLocalRunnerSecretNotice(BuildRequestPlatform resolvedPlatform)
        {
            if (resolvedPlatform != BuildRequestPlatform.Android &&
                resolvedPlatform != BuildRequestPlatform.iOS &&
                resolvedPlatform != BuildRequestPlatform.Both)
                return;

            EditorGUILayout.Space(6);
            EditorGUILayout.LabelField("Runner Credentials", EditorStyles.boldLabel);
            EditorGUILayout.HelpBox(
                "Test mode: BuildCommit serializes the Android keystore file, alias, keystore password, and alias password from BuildSetting into the committed request. Google Play, App Store Connect, and keychain credentials stay on the self-hosted Mac runner.",
                MessageType.Warning);
        }

        // Apply / Commit, Tag & Push 버튼 영역
        private void DrawButtons()
        {
            EditorGUILayout.BeginHorizontal();

            if (GUILayout.Button("Apply Settings", GUILayout.Height(30)))
            {
                ApplyPlayerSettings();
            }

            GUI.backgroundColor = new Color(0.4f, 0.8f, 0.4f);
            using (new EditorGUI.DisabledScope(!CanCreateBuildCommitRequest()))
            {
                if (GUILayout.Button("Commit, Tag & Push", GUILayout.Height(30)))
                {
                    ExecuteCommitTagAndPush();
                }
            }
            GUI.backgroundColor = Color.white;

            EditorGUILayout.EndHorizontal();
        }

        // 실행 결과 로그 영역
        private void DrawLog()
        {
            EditorGUILayout.LabelField("Log", EditorStyles.boldLabel);

            _logScrollPosition = EditorGUILayout.BeginScrollView(
                _logScrollPosition,
                GUILayout.MinHeight(80),
                GUILayout.ExpandHeight(true)
            );

            foreach (var log in _logs)
            {
                EditorGUILayout.LabelField(log, EditorStyles.wordWrappedMiniLabel);
            }

            EditorGUILayout.EndScrollView();

            if (_logs.Count > 0)
            {
                if (GUILayout.Button("Clear Log", GUILayout.Width(80)))
                {
                    _logs.Clear();
                    Repaint();
                }
            }
        }

        #endregion

        #region Private Methods

        // BuildSettingsSO 자동 로드 (BuildSettingsWindow와 동일한 SO 공유)
        private void LoadSO()
        {
            string savedPath = EditorPrefs.GetString(SOPrefsKey, "");
            if (!string.IsNullOrEmpty(savedPath))
                _settings = AssetDatabase.LoadAssetAtPath<BuildSettingsSO>(savedPath);

            if (_settings == null)
                _settings = BuildSettingsSO.FindOrCreateSettingsAsset();

            if (_settings != null)
                _serializedSettings = new SerializedObject(_settings);

            int savedProfile = EditorPrefs.GetInt(DistributionProfilePrefsKey, (int)BuildRequestDistributionProfile.Actionfit);
            if (System.Enum.IsDefined(typeof(BuildRequestDistributionProfile), savedProfile))
                _distributionProfile = (BuildRequestDistributionProfile)savedProfile;
        }

        // PlayerSettings에 버전/번들ID 적용
        private void ApplyPlayerSettings()
        {
            if (_settings == null) return;

            ApplySerializedIfModified();

            BuildSettingsApplier.ApplyVersionSettings(_settings);
            AddLog($"[Apply] version={_settings.buildVersion}, bundleNo={_settings.bundleNo}");
        }

        // PlayerSettings 적용 후 저장 커밋을 푸시하고, 빌드 요청 태그를 푸시한다.
        private void ExecuteCommitTagAndPush()
        {
            if (_settings == null) return;

            ApplySerializedIfModified();

            if (!CanCreateBuildCommitRequest())
            {
                AddLog("[ERROR] Platform is not selected.");
                EditorUtility.DisplayDialog(
                    "Commit, Tag & Push",
                    "Platform을 선택해야 BuildCommit request를 커밋할 수 있습니다.",
                    "OK");
                Repaint();
                return;
            }

            string version = _settings.buildVersion;
            string bundleNo = _settings.bundleNo;
            string commitMessage = CreateCommitMessage(version, bundleNo);
            string tagPreview = CreateBuildTag(version, bundleNo, "commit");

            if (!EditorUtility.DisplayDialog(
                    "Commit, Tag & Push",
                    $"다음 저장 커밋과 빌드 태그를 푸시합니다:\n\n{commitMessage}\n{tagPreview}\n\n계속하시겠습니까?",
                    "Push", "Cancel"))
                return;

            _logs.Clear();

            ApplyPlayerSettings();
            if (!SaveBuildRequest())
            {
                Repaint();
                return;
            }

            string addResult = RunGitCommand("add .");
            if (addResult == null) { Repaint(); return; }
            AddLog($"[git add] {addResult}");

            string commitResult = RunGitCommand($"commit --allow-empty -m \"{commitMessage}\"");
            if (commitResult == null) { Repaint(); return; }
            AddLog($"[git commit] {commitResult}");

            string pushResult = RunGitCommand("push");
            if (pushResult == null) { Repaint(); return; }
            AddLog($"[git push] {pushResult}");

            string commitSha = RunGitCommand("rev-parse HEAD");
            if (commitSha == null) { Repaint(); return; }

            string shortSha = RunGitCommand("rev-parse --short HEAD");
            if (shortSha == null) { Repaint(); return; }

            string buildTag = CreateBuildTag(version, bundleNo, shortSha);
            string tagResult = RunGitCommand($"tag {buildTag} {commitSha}");
            if (tagResult == null) { Repaint(); return; }
            AddLog($"[git tag] {buildTag} -> {shortSha}");

            string tagPushResult = RunGitCommand($"push origin refs/tags/{buildTag}");
            if (tagPushResult == null) { Repaint(); return; }
            AddLog($"[git push tag] {tagPushResult}");

            AddLog("Done.");
            Debug.Log($"[BuildCommitWindow] Commit, tag & push complete: {commitMessage}, {buildTag}");

            Repaint();
        }

        private void UpdateWorkflowFile()
        {
            if (BuildCommitWorkflowSyncUtility.IsWorkflowCurrent())
            {
                AddLog("[Workflow] Already up to date.");
                EditorUtility.DisplayDialog(
                    "GitHub Workflow",
                    $"{BuildCommitWorkflowSyncUtility.WorkflowRelativePath} and {BuildCommitWorkflowSyncUtility.ScriptRelativePath} are already up to date.",
                    "OK");
                Repaint();
                return;
            }

            string action = BuildCommitWorkflowSyncUtility.WorkflowExists() ? "Overwrite" : "Create";
            if (!EditorUtility.DisplayDialog(
                    "Update GitHub Workflow",
                    $"Copy the package workflow assets to:\n{BuildCommitWorkflowSyncUtility.WorkflowRelativePath}\n{BuildCommitWorkflowSyncUtility.ScriptRelativePath}\n\n{BuildCommitWorkflowSyncUtility.GetStatusMessage()}",
                    action,
                    "Cancel"))
                return;

            if (BuildCommitWorkflowSyncUtility.TrySync(out string message))
            {
                AddLog($"[Workflow] {message}");
                Debug.Log($"[BuildCommitWindow] {message}");
            }
            else
            {
                AddLog($"[ERROR] {message}");
                Debug.LogError($"[BuildCommitWindow] {message}");
            }

            Repaint();
        }

        private string CreateCommitMessage(string version, string bundleNo)
        {
            return $"[BuildRequest] v{version}({bundleNo})";
        }

        private string CreateBuildTag(string version, string bundleNo, string uniqueSuffix)
        {
            string platform = GetPlatformToken(_requestPlatform);
            string upload = GetUploadToken(_uploadTarget);
            string safeVersion = SanitizeTagSegment(version, "version");
            string safeBundle = SanitizeTagSegment(bundleNo, "0");
            string safeSuffix = SanitizeTagSegment(uniqueSuffix, "commit");

            return $"{BuildTagPrefix}/{platform}-{upload}/{safeVersion}/{safeBundle}-{safeSuffix}";
        }

        private string GetPlatformToken(BuildRequestPlatform platform)
        {
            BuildRequestPlatform resolvedPlatform = ResolvePlatform(platform);
            switch (resolvedPlatform)
            {
                case BuildRequestPlatform.None:
                    return "none";
                case BuildRequestPlatform.Android:
                    return "aos";
                case BuildRequestPlatform.iOS:
                    return "ios";
                case BuildRequestPlatform.Both:
                    return "both";
                default:
                    return "current";
            }
        }

        private bool CanCreateBuildCommitRequest()
        {
            return _requestPlatform != BuildRequestPlatform.None;
        }

        private BuildRequestPlatform ResolvePlatform(BuildRequestPlatform platform)
        {
            if (platform != BuildRequestPlatform.Current)
                return platform;

            switch (EditorUserBuildSettings.activeBuildTarget)
            {
                case BuildTarget.Android:
                    return BuildRequestPlatform.Android;
                case BuildTarget.iOS:
                    return BuildRequestPlatform.iOS;
                default:
                    return BuildRequestPlatform.Current;
            }
        }

        private void ApplyDefaultRequestOptionsForPlatform(BuildRequestPlatform resolvedPlatform)
        {
            switch (resolvedPlatform)
            {
                case BuildRequestPlatform.Android:
                    _requestKind = BuildRequestKind.AndroidAab;
                    _uploadTarget = BuildRequestUploadTarget.GooglePlayInternal;
                    break;
                case BuildRequestPlatform.iOS:
                    _requestKind = BuildRequestKind.iOSXcodeProject;
                    _uploadTarget = BuildRequestUploadTarget.TestFlight;
                    break;
                case BuildRequestPlatform.Both:
                    _requestKind = BuildRequestKind.AndroidAabAndiOSXcodeProject;
                    _uploadTarget = BuildRequestUploadTarget.GooglePlayInternalAndTestFlight;
                    break;
                default:
                    _requestKind = BuildRequestKind.Default;
                    _uploadTarget = BuildRequestUploadTarget.None;
                    break;
            }
        }

        private string GetUploadToken(BuildRequestUploadTarget uploadTarget)
        {
            switch (uploadTarget)
            {
                case BuildRequestUploadTarget.GooglePlayInternal:
                    return "play";
                case BuildRequestUploadTarget.TestFlight:
                    return "testflight";
                case BuildRequestUploadTarget.GooglePlayInternalAndTestFlight:
                    return "store";
                default:
                    return "none";
            }
        }

        private string SanitizeTagSegment(string value, string fallback)
        {
            if (string.IsNullOrWhiteSpace(value))
                return fallback;

            var builder = new StringBuilder(value.Length);
            bool lastDash = false;

            foreach (char character in value.Trim())
            {
                bool safeCharacter =
                    (character >= 'a' && character <= 'z') ||
                    (character >= 'A' && character <= 'Z') ||
                    (character >= '0' && character <= '9') ||
                    character == '.' ||
                    character == '_' ||
                    character == '-';

                if (safeCharacter)
                {
                    builder.Append(character);
                    lastDash = false;
                    continue;
                }

                if (!lastDash)
                {
                    builder.Append('-');
                    lastDash = true;
                }
            }

            string result = builder.ToString().Trim('.', '_', '-');
            while (result.Contains(".."))
                result = result.Replace("..", ".");

            if (result.EndsWith(".lock", System.StringComparison.OrdinalIgnoreCase))
                result += "-tag";

            return string.IsNullOrEmpty(result) ? fallback : result;
        }

        // BuildCommit 커밋에 포함할 원격 빌드 요청 파일 생성
        private bool SaveBuildRequest()
        {
            if (!CanCreateBuildCommitRequest())
            {
                AddLog("[ERROR] Platform is not selected.");
                return false;
            }

            var request = BuildRequestUtility.Create(
                _settings,
                _requestPlatform,
                _requestKind,
                _uploadTarget,
                _distributionProfile);
            if (request == null) return false;

            bool saved = BuildRequestUtility.Save(request);
            if (saved) AddLog($"[BuildRequest] {BuildRequestUtility.RelativePath}");
            return saved;
        }

        // git 명령어 실행 후 결과 반환 (실패 시 null 반환)
        private string RunGitCommand(string args)
        {
            string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = args,
                    WorkingDirectory = projectRoot,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using (var process = Process.Start(startInfo))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();

                    if (process.ExitCode != 0)
                    {
                        string errorMsg = string.IsNullOrEmpty(error) ? output : error;
                        AddLog($"[ERROR] git {args}: {errorMsg.Trim()}");
                        Debug.LogError($"[BuildCommitWindow] git {args} failed: {errorMsg.Trim()}");
                        return null;
                    }

                    return string.IsNullOrEmpty(output) ? "OK" : output.Trim();
                }
            }
            catch (System.Exception e)
            {
                AddLog($"[EXCEPTION] {e.Message}");
                Debug.LogError($"[BuildCommitWindow] Exception on git {args}: {e.Message}");
                return null;
            }
        }

        // 로그 항목 추가
        private void AddLog(string message)
        {
            _logs.Add(message);
        }

        // SerializedObject 변경사항을 SO에 반영 및 저장
        private void ApplySerializedIfModified()
        {
            if (_serializedSettings == null || !_serializedSettings.hasModifiedProperties) return;
            _serializedSettings.ApplyModifiedProperties();
            EditorUtility.SetDirty(_settings);
            AssetDatabase.SaveAssets();
        }

        #endregion
    }
}

#endif
