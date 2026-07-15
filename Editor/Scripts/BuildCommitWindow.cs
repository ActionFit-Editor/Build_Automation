#if UNITY_EDITOR

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;
using Process = System.Diagnostics.Process;
using ProcessStartInfo = System.Diagnostics.ProcessStartInfo;

namespace ActionFit.BuildAutomation.Editor
{
    public class BuildCommitWindow : EditorWindow
    {
        #region Fields

        private const string DistributionProfilePrefsKey = "BuildCommitDistributionProfile";
        private const string LegacySlackMentionsPrefsKey = "BuildCommitSlackMentions";
        private const string AutoSyncWorkflowAssetsPrefsKey = "BuildCommitAutoSyncWorkflowAssets";
        private const string BuildTagPrefix = "build";
        private const string ActionFitPackageManagerMenuPath = "Tools/Package/Custom Package Manager/Package Manager";
        private const string GitHubAuthPackageId = "com.actionfit.githubauth";
        private const string GitHubAuthMinimumVersion = "1.0.6";
        private const string GitHubAuthPreflightTypeName = "ActionFit.GitHubAuth.Editor.GitHubAuthPreflight, com.actionfit.githubauth.Editor";

        private ScriptableObject _settings; // 빌드 설정 SO
        private SerializedObject _serializedSettings; // SO 직렬화 래퍼
        private BuildAutomationSettingsSO _automationSettings; // 자동 빌드 공유 설정 SO
        private SerializedObject _serializedAutomationSettings; // 자동 빌드 SO 직렬화 래퍼
        private BuildRequestPlatform _requestPlatform = BuildRequestPlatform.None; // 원격 빌드 플랫폼
        private BuildRequestKind _requestKind = BuildRequestKind.Default; // 원격 빌드 종류
        private BuildRequestUploadTarget _uploadTarget = BuildRequestUploadTarget.None; // 업로드 대상
        private BuildRequestDistributionProfile _distributionProfile = BuildRequestDistributionProfile.Actionfit; // 배포 계정 프로필
        private bool _autoSyncWorkflowAssets = true; // Commit 전 패키지 workflow/scripts 자동 동기화

        private Vector2 _contentScrollPosition; // 창 전체 스크롤 위치
        private Vector2 _logScrollPosition; // 로그 스크롤 위치
        private readonly List<string> _logs = new(); // 실행 결과 로그 목록

        #endregion

        #region Window

        [MenuItem("Tools/Package/Build Automation/AutoBuild", false, 21)]
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
            _contentScrollPosition = EditorGUILayout.BeginScrollView(
                _contentScrollPosition,
                false,
                true,
                GUILayout.ExpandHeight(true));

            try
            {
                EditorGUILayout.Space(8);

                if (!BuildSettingBridge.EnsureAvailable(false))
                {
                    EditorGUILayout.HelpBox(
                        $"Build Setting package is required. Install or update Build Automation through ActionFit Package Manager so `{BuildSettingBridge.PackageId}@{BuildSettingBridge.MinimumVersion}` is applied.",
                        MessageType.Warning);
                    if (GUILayout.Button("Open ActionFit Package Manager", GUILayout.Height(24)))
                        OpenActionFitPackageManagerOrShowGuide();
                    return;
                }

                DrawSOField();
                EditorGUILayout.Space(8);

                if (_settings == null || _automationSettings == null)
                    LoadSO();

                if (_settings == null)
                {
                    EditorGUILayout.HelpBox("BuildSettingsSO를 연결해주세요.", MessageType.Warning);
                    return;
                }

                if (_automationSettings == null)
                {
                    EditorGUILayout.HelpBox("BuildAutomationSettingsSO를 연결해주세요.", MessageType.Warning);
                    return;
                }

                _serializedSettings?.Update();
                _serializedAutomationSettings?.Update();

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
            finally
            {
                EditorGUILayout.EndScrollView();
            }
        }

        #endregion

        #region Draw Methods

        // SO ObjectField 표시
        private void DrawSOField()
        {
            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.PrefixLabel("Build Settings");

            EditorGUI.BeginChangeCheck();
            _settings = EditorGUILayout.ObjectField(_settings, BuildSettingBridge.SettingsType, false) as ScriptableObject;
            if (EditorGUI.EndChangeCheck())
            {
                if (_settings != null)
                {
                    _serializedSettings = new SerializedObject(_settings);
                    EditorPrefs.SetString(BuildSettingBridge.SOPrefsKey, AssetDatabase.GetAssetPath(_settings));
                }
                else
                {
                    _serializedSettings = null;
                }
            }

            EditorGUILayout.EndHorizontal();

            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.PrefixLabel("Automation Settings");

            EditorGUI.BeginChangeCheck();
            _automationSettings = (BuildAutomationSettingsSO)EditorGUILayout.ObjectField(_automationSettings, typeof(BuildAutomationSettingsSO), false);
            if (EditorGUI.EndChangeCheck())
            {
                if (_automationSettings != null)
                {
                    _serializedAutomationSettings = new SerializedObject(_automationSettings);
                    EditorPrefs.SetString(BuildAutomationSettingsSO.SOPrefsKey, AssetDatabase.GetAssetPath(_automationSettings));
                    MigrateSlackMentionsFromEditorPrefs();
                }
                else
                {
                    _serializedAutomationSettings = null;
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

            DrawDevelopmentBuildSetting();
            DrawBuildSymbolSettings();
            DrawSlackMentions();

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
                $"{BuildRequestUtility.RelativePath} will be stored at the Git repository root. GitHub Actions will build when the build tag is pushed.",
                MessageType.Info);
        }

        private void DrawDevelopmentBuildSetting()
        {
            SerializedProperty developmentBuildProp = _serializedSettings.FindProperty("developmentBuild");
            if (developmentBuildProp == null)
            {
                EditorGUILayout.HelpBox(
                    $"BuildSettingsSO does not expose developmentBuild. Update {BuildSettingBridge.PackageId} to {BuildSettingBridge.MinimumVersion} or newer.",
                    MessageType.Error);
                return;
            }

            EditorGUILayout.Space(4);
            EditorGUILayout.PropertyField(
                developmentBuildProp,
                new GUIContent(
                    "Development Build",
                    "Unity BuildOptions.Development를 Android/iOS 로컬 및 CI Player 빌드에 적용합니다. DEV scripting define과는 별도 설정입니다."));
        }

        private void DrawBuildSymbolSettings()
        {
            SerializedProperty symbolSettingProp =
                _serializedAutomationSettings.FindProperty("autoConfigureBuildSymbols");
            if (symbolSettingProp == null)
            {
                EditorGUILayout.HelpBox(
                    "BuildAutomationSettingsSO does not expose autoConfigureBuildSymbols. Update com.actionfit.buildautomation.",
                    MessageType.Warning);
                return;
            }

            EditorGUILayout.Space(4);
            bool customSymbolsAvailable =
                CustomSymbolsBridge.TryEnsureAvailable(out string customSymbolsError);
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.PropertyField(
                    symbolSettingProp,
                    new GUIContent(
                        "자동 빌드 심볼 세팅",
                        "체크 시 Custom Symbols의 Build 설정을 러너 빌드 전에 적용하고, 새 Unity 프로세스에서 빌드합니다."));

                using (new EditorGUI.DisabledScope(!customSymbolsAvailable))
                {
                    if (GUILayout.Button("Custom Symbols 열기", GUILayout.Width(150), GUILayout.Height(22)))
                        CustomSymbolsBridge.OpenWindow();
                }
            }

            if (symbolSettingProp.boolValue && !customSymbolsAvailable)
                EditorGUILayout.HelpBox(customSymbolsError, MessageType.Error);
        }

        private void DrawWorkflowSync()
        {
            EditorGUILayout.LabelField("GitHub Workflow", EditorStyles.boldLabel);

            EditorGUI.BeginChangeCheck();
            _autoSyncWorkflowAssets = EditorGUILayout.Toggle(
                new GUIContent("Auto Sync Build Files", "Commit 전에 BuildAutomation 패키지의 workflow/scripts를 Git 저장소 루트 .github 폴더로 동기화합니다."),
                _autoSyncWorkflowAssets);
            if (EditorGUI.EndChangeCheck())
                EditorPrefs.SetBool(AutoSyncWorkflowAssetsPrefsKey, _autoSyncWorkflowAssets);

            bool isCurrent = BuildCommitWorkflowSyncUtility.IsWorkflowCurrent();
            EditorGUILayout.HelpBox(
                BuildCommitWorkflowSyncUtility.GetStatusMessage(),
                isCurrent ? MessageType.Info : MessageType.Warning);

            if (GUILayout.Button("Update GitHub Workflow", GUILayout.Height(26)))
            {
                UpdateWorkflowFile();
            }
        }

        private void DrawSlackMentions()
        {
            SerializedProperty mentionsProp = _serializedAutomationSettings.FindProperty("buildCommitSlackMentions");
            if (mentionsProp == null)
            {
                EditorGUILayout.HelpBox("BuildAutomationSettingsSO does not expose buildCommitSlackMentions. Update com.actionfit.buildautomation.", MessageType.Warning);
                return;
            }

            EditorGUILayout.Space(4);
            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField(
                    new GUIContent("Slack Mentions", "Shared in BuildAutomationSettingsSO. Checked rows are serialized into the BuildCommit request; Memo is only for identifying entries in this window."),
                    EditorStyles.boldLabel);
                GUILayout.FlexibleSpace();
                if (GUILayout.Button("+", GUILayout.Width(28)))
                {
                    int index = mentionsProp.arraySize;
                    mentionsProp.InsertArrayElementAtIndex(index);
                    SerializedProperty entryProp = mentionsProp.GetArrayElementAtIndex(index);
                    entryProp.FindPropertyRelative("enabled").boolValue = true;
                    entryProp.FindPropertyRelative("memberId").stringValue = "";
                    entryProp.FindPropertyRelative("memo").stringValue = "";
                }
            }

            if (mentionsProp.arraySize == 0)
            {
                EditorGUILayout.HelpBox("Optional. Add Slack member IDs to mention in build result notifications. Entries are saved in BuildAutomationSettingsSO and shared with the project.", MessageType.None);
                return;
            }

            using (new EditorGUILayout.HorizontalScope())
            {
                EditorGUILayout.LabelField(new GUIContent("Mention", "Checked rows are sent as Slack mentions."), EditorStyles.miniBoldLabel, GUILayout.Width(60));
                EditorGUILayout.LabelField("Member ID", EditorStyles.miniBoldLabel, GUILayout.Width(170));
                EditorGUILayout.LabelField("Memo", EditorStyles.miniBoldLabel);
                GUILayout.Space(32);
            }

            int removeIndex = -1;
            for (int i = 0; i < mentionsProp.arraySize; i++)
            {
                SerializedProperty entryProp = mentionsProp.GetArrayElementAtIndex(i);
                SerializedProperty enabledProp = entryProp.FindPropertyRelative("enabled");
                SerializedProperty memberIdProp = entryProp.FindPropertyRelative("memberId");
                SerializedProperty memoProp = entryProp.FindPropertyRelative("memo");

                using (new EditorGUILayout.HorizontalScope())
                {
                    enabledProp.boolValue = EditorGUILayout.Toggle(enabledProp.boolValue, GUILayout.Width(60));
                    memberIdProp.stringValue = EditorGUILayout.TextField(memberIdProp.stringValue ?? "", GUILayout.Width(170));
                    memoProp.stringValue = EditorGUILayout.TextField(memoProp.stringValue ?? "");

                    if (GUILayout.Button("-", GUILayout.Width(28)))
                        removeIndex = i;
                }
            }

            if (removeIndex >= 0)
                mentionsProp.DeleteArrayElementAtIndex(removeIndex);
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
                "Android BuildRequest에는 keystore 파일 Base64와 keystore/alias 비밀번호가 포함됩니다. 값이 없을 때만 self-hosted runner의 Android signing 환경값을 fallback으로 사용합니다. Google Play, App Store Connect, certificate와 keychain credential은 runner 로컬 secret bundle에서 읽습니다.",
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

            float logHeight = Mathf.Clamp(position.height * 0.25f, 80f, 180f);
            _logScrollPosition = EditorGUILayout.BeginScrollView(
                _logScrollPosition,
                GUILayout.Height(logHeight)
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
            if (!BuildSettingBridge.EnsureAvailable(false))
                return;

            string savedPath = EditorPrefs.GetString(BuildSettingBridge.SOPrefsKey, "");
            if (!string.IsNullOrEmpty(savedPath))
                _settings = AssetDatabase.LoadAssetAtPath(savedPath, BuildSettingBridge.SettingsType) as ScriptableObject;

            if (_settings == null)
                _settings = BuildSettingBridge.FindOrCreateSettingsAsset();

            if (_settings != null)
                _serializedSettings = new SerializedObject(_settings);

            _automationSettings = BuildAutomationSettingsSO.FindOrCreateSettingsAsset();
            if (_automationSettings != null)
            {
                _serializedAutomationSettings = new SerializedObject(_automationSettings);
                MigrateSlackMentionsFromEditorPrefs();
            }

            int savedProfile = EditorPrefs.GetInt(DistributionProfilePrefsKey, (int)BuildRequestDistributionProfile.Actionfit);
            if (System.Enum.IsDefined(typeof(BuildRequestDistributionProfile), savedProfile))
                _distributionProfile = (BuildRequestDistributionProfile)savedProfile;

            _autoSyncWorkflowAssets = EditorPrefs.GetBool(AutoSyncWorkflowAssetsPrefsKey, true);
        }

        private void MigrateSlackMentionsFromEditorPrefs()
        {
            if (_automationSettings == null) return;

            string saved = EditorPrefs.GetString(LegacySlackMentionsPrefsKey, "");
            if (string.IsNullOrWhiteSpace(saved))
                return;

            if (_automationSettings.buildCommitSlackMentions == null)
                _automationSettings.buildCommitSlackMentions = new List<BuildAutomationSettingsSO.SlackMentionEntry>();

            if (_automationSettings.buildCommitSlackMentions.Count > 0)
            {
                EditorPrefs.DeleteKey(LegacySlackMentionsPrefsKey);
                return;
            }

            string trimmed = saved.TrimStart();
            int migratedCount = 0;
            if (trimmed.StartsWith("{"))
            {
                try
                {
                    var prefs = JsonUtility.FromJson<LegacySlackMentionPrefs>(saved);
                    if (prefs?.Entries != null)
                    {
                        foreach (var entry in prefs.Entries)
                        {
                            if (entry == null) continue;
                            string memberId = entry.MemberId?.Trim();
                            if (string.IsNullOrEmpty(memberId)) continue;

                            _automationSettings.buildCommitSlackMentions.Add(new BuildAutomationSettingsSO.SlackMentionEntry
                            {
                                enabled = true,
                                memberId = memberId,
                                memo = entry.Memo ?? ""
                            });
                            migratedCount++;
                        }
                    }
                }
                catch
                {
                    _automationSettings.buildCommitSlackMentions.Clear();
                    migratedCount = 0;
                }
            }
            else
            {
                foreach (string token in SplitSlackMentionText(saved))
                {
                    _automationSettings.buildCommitSlackMentions.Add(new BuildAutomationSettingsSO.SlackMentionEntry
                    {
                        enabled = true,
                        memberId = token,
                        memo = ""
                    });
                    migratedCount++;
                }
            }

            EditorPrefs.DeleteKey(LegacySlackMentionsPrefsKey);

            if (migratedCount <= 0) return;

            EditorUtility.SetDirty(_automationSettings);
            AssetDatabase.SaveAssets();
            _serializedAutomationSettings = new SerializedObject(_automationSettings);
            Debug.Log($"[BuildCommitWindow] Migrated {migratedCount} Slack mention entries from EditorPrefs to BuildAutomationSettingsSO.");
        }

        private string[] GetSlackMentionMemberIds()
        {
            var result = new List<string>();
            if (_automationSettings?.buildCommitSlackMentions == null)
                return result.ToArray();

            foreach (var entry in _automationSettings.buildCommitSlackMentions)
            {
                if (entry == null || !entry.enabled) continue;
                string memberId = entry.memberId?.Trim();
                if (string.IsNullOrEmpty(memberId) || result.Contains(memberId)) continue;
                result.Add(memberId);
            }

            return result.ToArray();
        }

        private static string[] SplitSlackMentionText(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return new string[0];
            return value
                .Replace(",", " ")
                .Replace("\r", " ")
                .Replace("\n", " ")
                .Split(new[] { ' ', '\t' }, System.StringSplitOptions.RemoveEmptyEntries);
        }

        // PlayerSettings에 버전/번들ID 적용
        private void ApplyPlayerSettings()
        {
            if (_settings == null) return;

            ApplySerializedIfModified();

            BuildSettingBridge.ApplyVersionSettings(_settings);
            AddLog($"[Apply] version={BuildSettingBridge.GetString(_settings, "buildVersion")}, bundleNo={BuildSettingBridge.GetString(_settings, "bundleNo")}");
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

            string version = BuildSettingBridge.GetString(_settings, "buildVersion");
            string bundleNo = BuildSettingBridge.GetString(_settings, "bundleNo");
            string commitMessage = CreateCommitMessage(version, bundleNo);
            string tagPreview = CreateBuildTag(version, bundleNo, "commit");

            _logs.Clear();

            if (!EnsureGitHubAuthForCommitPush())
            {
                Repaint();
                return;
            }

            if (!EditorUtility.DisplayDialog(
                    "Commit, Tag & Push",
                    $"다음 저장 커밋과 빌드 태그를 푸시합니다:\n\n{commitMessage}\n{tagPreview}\n\n계속하시겠습니까?",
                    "Push", "Cancel"))
                return;

            if (!SyncWorkflowAssetsForCommit())
            {
                Repaint();
                return;
            }

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

        private bool EnsureGitHubAuthForCommitPush()
        {
            Type preflightType = Type.GetType(GitHubAuthPreflightTypeName);
            if (preflightType == null)
            {
                AddLog($"[ERROR] AI GitHub package is required. Install {GitHubAuthPackageId}@{GitHubAuthMinimumVersion} through ActionFit Package Manager and reopen Unity.");
                ShowGitHubAuthMissingDialog();
                return false;
            }

            MethodInfo method = GetGitHubAuthEnsureMethod(preflightType);
            if (method == null)
            {
                AddLog($"[ERROR] AI GitHub preflight API is not available. Update {GitHubAuthPackageId} to {GitHubAuthMinimumVersion} or newer through ActionFit Package Manager.");
                ShowGitHubAuthMissingDialog();
                return false;
            }

            if (!BuildRequestUtility.TryGetRepositoryRoot(out string repositoryRoot, out string repositoryError))
            {
                AddLog($"[ERROR] {repositoryError}");
                return false;
            }

            object[] args = { repositoryRoot, "BuildCommit Commit, Tag & Push", null };
            bool isReady;
            object result;

            try
            {
                isReady = (bool)method.Invoke(null, args);
                result = args[2];
            }
            catch (System.Exception exception)
            {
                AddLog($"[ERROR] [AI GitHub] {exception.Message}");
                Debug.LogError($"[BuildCommitWindow] AI GitHub preflight failed: {exception}");
                return false;
            }

            string message = GetStringProperty(result, "Message");
            string failedCommand = GetStringProperty(result, "FailedCommand");
            string details = GetStringProperty(result, "Details");

            if (isReady)
            {
                AddLog($"[AI GitHub] {message}");
                return true;
            }

            AddLog($"[ERROR] [AI GitHub] {message}");
            if (!string.IsNullOrEmpty(failedCommand))
                AddLog($"[AI GitHub] Failed command: {failedCommand}");
            if (!string.IsNullOrEmpty(details))
                AddLog(details);
            return false;
        }

        private static void ShowGitHubAuthMissingDialog()
        {
            int result = EditorUtility.DisplayDialogComplex(
                "AI GitHub Required",
                $"BuildCommit push preflight requires `{GitHubAuthPackageId}@{GitHubAuthMinimumVersion}`.\n\n" +
                "Install or update Build Automation through ActionFit Package Manager so its declared dependencies are applied.\n\n" +
                "For GitHub credential setup, read AI GitHub README or ask AI for the GitHub authentication guide.",
                "Open Package Manager",
                "OK",
                "");

            if (result == 0)
                OpenActionFitPackageManagerOrShowGuide();
        }

        private static void OpenActionFitPackageManagerOrShowGuide()
        {
            if (EditorApplication.ExecuteMenuItem(ActionFitPackageManagerMenuPath))
                return;

                EditorUtility.DisplayDialog(
                    "ActionFit Package Manager",
                    "ActionFit Package Manager is not available in this project.\n\n" +
                $"Install the ActionFit Package Manager first, or manually add Build Automation plus `{BuildSettingBridge.PackageId}@{BuildSettingBridge.MinimumVersion}` and `{GitHubAuthPackageId}@{GitHubAuthMinimumVersion}` Git UPM URLs to the project manifest.",
                "OK");
        }

        private static MethodInfo GetGitHubAuthEnsureMethod(Type preflightType)
        {
            foreach (MethodInfo method in preflightType.GetMethods(BindingFlags.Public | BindingFlags.Static))
            {
                if (method.Name != "EnsureProjectGitHubPushAccess")
                    continue;

                ParameterInfo[] parameters = method.GetParameters();
                if (parameters.Length != 3)
                    continue;
                if (parameters[0].ParameterType != typeof(string) || parameters[1].ParameterType != typeof(string))
                    continue;
                if (!parameters[2].ParameterType.IsByRef)
                    continue;

                return method;
            }

            return null;
        }

        private static string GetStringProperty(object source, string propertyName)
        {
            if (source == null || string.IsNullOrEmpty(propertyName))
                return "";

            PropertyInfo property = source.GetType().GetProperty(propertyName, BindingFlags.Public | BindingFlags.Instance);
            return property?.GetValue(source) as string ?? "";
        }

        private bool SyncWorkflowAssetsForCommit()
        {
            if (!_autoSyncWorkflowAssets)
                return true;

            if (BuildCommitWorkflowSyncUtility.IsWorkflowCurrent())
            {
                AddLog("[Workflow Auto Sync] Already up to date.");
                return true;
            }

            if (BuildCommitWorkflowSyncUtility.TrySync(out string message))
            {
                AddLog($"[Workflow Auto Sync] {message}");
                Debug.Log($"[BuildCommitWindow] Auto synced workflow assets: {message}");
                return true;
            }

            AddLog($"[ERROR] {message}");
            Debug.LogError($"[BuildCommitWindow] Auto workflow sync failed: {message}");
            EditorUtility.DisplayDialog(
                "Commit, Tag & Push",
                $"BuildAutomation package workflow assets could not be synced.\n\n{message}",
                "OK");
            return false;
        }

        private void UpdateWorkflowFile()
        {
            if (BuildCommitWorkflowSyncUtility.IsWorkflowCurrent())
            {
                AddLog("[Workflow] Already up to date.");
                EditorUtility.DisplayDialog(
                    "GitHub Workflow",
                    $"{BuildCommitWorkflowSyncUtility.GetWorkflowAssetSummary()} are already up to date.",
                    "OK");
                Repaint();
                return;
            }

            string action = BuildCommitWorkflowSyncUtility.WorkflowExists() ? "Overwrite" : "Create";
            if (!EditorUtility.DisplayDialog(
                    "Update GitHub Workflow",
                    $"Copy the package workflow assets to:\n{BuildCommitWorkflowSyncUtility.GetWorkflowAssetSummary()}\n\n{BuildCommitWorkflowSyncUtility.GetStatusMessage()}",
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

            if (_automationSettings != null &&
                _automationSettings.autoConfigureBuildSymbols &&
                !CustomSymbolsBridge.HasSettingsAsset())
            {
                AddLog("[ERROR] CustomSymbolsSO could not be found or created.");
                EditorUtility.DisplayDialog(
                    "Custom Symbols Required",
                    "Custom Symbols 설정 에셋을 찾거나 기본 경로에 생성하지 못했습니다. Console 로그와 `Assets/_Data/_CustomSymbols` 경로를 확인하세요.",
                    "OK");
                return false;
            }

            var request = BuildRequestUtility.Create(
                _settings,
                _requestPlatform,
                _requestKind,
                _uploadTarget,
                _distributionProfile,
                GetSlackMentionMemberIds(),
                _automationSettings != null && _automationSettings.autoConfigureBuildSymbols);
            if (request == null) return false;

            bool saved = BuildRequestUtility.Save(request);
            if (saved) AddLog($"[BuildRequest] {BuildRequestUtility.RelativePath}");
            return saved;
        }

        // git 명령어 실행 후 결과 반환 (실패 시 null 반환)
        private string RunGitCommand(string args)
        {
            if (!BuildRequestUtility.TryGetRepositoryRoot(out string repositoryRoot, out string repositoryError))
            {
                AddLog($"[ERROR] {repositoryError}");
                return null;
            }

            try
            {
                GitCommandResult result = GitProcessRunner.RunWithIndexLockRetry(repositoryRoot, args);
                if (result.IndexLockRetryCount > 0)
                {
                    string retryMessage = result.ExitCode == 0
                        ? $"git {args} recovered after {result.IndexLockRetryCount} index.lock retry attempt(s)."
                        : $"git {args} still failed after {result.IndexLockRetryCount} index.lock retry attempt(s).";
                    AddLog($"[git retry] {retryMessage}");
                    Debug.LogWarning($"[BuildCommitWindow] Git retry: {retryMessage}");
                }

                if (result.TimedOut)
                {
                    string timeoutMessage =
                        $"git {args} timed out after {GitProcessRunner.DefaultTimeoutMilliseconds / 1000} seconds.";
                    AddLog($"[ERROR] {timeoutMessage}");
                    Debug.LogError($"[BuildCommitWindow] {timeoutMessage}");
                    return null;
                }

                if (result.ExitCode != 0)
                {
                    string errorMsg = string.IsNullOrEmpty(result.Error) ? result.Output : result.Error;
                    AddLog($"[ERROR] git {args}: {errorMsg.Trim()}");
                    Debug.LogError($"[BuildCommitWindow] git {args} failed: {errorMsg.Trim()}");
                    return null;
                }

                return string.IsNullOrEmpty(result.Output) ? "OK" : result.Output.Trim();
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
            bool changed = false;

            if (_serializedSettings != null && _serializedSettings.hasModifiedProperties)
            {
                _serializedSettings.ApplyModifiedProperties();
                EditorUtility.SetDirty(_settings);
                changed = true;
            }

            if (_serializedAutomationSettings != null && _serializedAutomationSettings.hasModifiedProperties)
            {
                _serializedAutomationSettings.ApplyModifiedProperties();
                EditorUtility.SetDirty(_automationSettings);
                changed = true;
            }

            if (!changed) return;
            AssetDatabase.SaveAssets();
        }

        [System.Serializable]
        private sealed class LegacySlackMentionPrefs
        {
            public LegacySlackMentionEntry[] Entries = new LegacySlackMentionEntry[0];
        }

        [System.Serializable]
        private sealed class LegacySlackMentionEntry
        {
            public string MemberId = "";
            public string Memo = "";
        }

        #endregion
    }

    internal readonly struct GitCommandResult
    {
        internal readonly int ExitCode;
        internal readonly string Output;
        internal readonly string Error;
        internal readonly bool TimedOut;
        internal readonly int IndexLockRetryCount;

        internal GitCommandResult(
            int exitCode,
            string output,
            string error,
            bool timedOut,
            int indexLockRetryCount = 0)
        {
            ExitCode = exitCode;
            Output = output ?? "";
            Error = error ?? "";
            TimedOut = timedOut;
            IndexLockRetryCount = indexLockRetryCount;
        }
    }

    internal static class GitProcessRunner
    {
        internal const int DefaultTimeoutMilliseconds = 300000;
        internal const int DefaultIndexLockRetryCount = 20;
        internal const int DefaultIndexLockRetryDelayMilliseconds = 250;
        private const int TerminationWaitMilliseconds = 5000;

        internal static GitCommandResult RunWithIndexLockRetry(
            string workingDirectory,
            string arguments,
            int timeoutMilliseconds = DefaultTimeoutMilliseconds,
            int maxIndexLockRetries = DefaultIndexLockRetryCount,
            int indexLockRetryDelayMilliseconds = DefaultIndexLockRetryDelayMilliseconds)
        {
            if (maxIndexLockRetries < 0) throw new ArgumentOutOfRangeException(nameof(maxIndexLockRetries));
            if (indexLockRetryDelayMilliseconds < 0)
                throw new ArgumentOutOfRangeException(nameof(indexLockRetryDelayMilliseconds));

            GitCommandResult result = Run(workingDirectory, arguments, timeoutMilliseconds);
            int retryCount = 0;

            while (retryCount < maxIndexLockRetries && IsIndexLockContention(result))
            {
                retryCount++;
                if (indexLockRetryDelayMilliseconds > 0)
                    System.Threading.Thread.Sleep(indexLockRetryDelayMilliseconds);
                result = Run(workingDirectory, arguments, timeoutMilliseconds);
            }

            return new GitCommandResult(
                result.ExitCode,
                result.Output,
                result.Error,
                result.TimedOut,
                retryCount);
        }

        internal static bool IsIndexLockContention(GitCommandResult result)
        {
            if (result.TimedOut || result.ExitCode == 0) return false;

            string message = $"{result.Error}\n{result.Output}";
            return message.IndexOf("index.lock", StringComparison.OrdinalIgnoreCase) >= 0
                   && message.IndexOf("Unable to create", StringComparison.OrdinalIgnoreCase) >= 0
                   && message.IndexOf("File exists", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        internal static GitCommandResult Run(
            string workingDirectory,
            string arguments,
            int timeoutMilliseconds = DefaultTimeoutMilliseconds)
        {
            if (timeoutMilliseconds <= 0) throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));

            var startInfo = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };

            using (var process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException($"Could not start process: {startInfo.FileName}");

                Task<string> outputTask = process.StandardOutput.ReadToEndAsync();
                Task<string> errorTask = process.StandardError.ReadToEndAsync();
                var stopwatch = System.Diagnostics.Stopwatch.StartNew();

                if (!process.WaitForExit(timeoutMilliseconds))
                {
                    TryTerminateProcessTree(process);
                    return new GitCommandResult(
                        -1,
                        GetCompletedOutput(outputTask),
                        GetCompletedOutput(errorTask),
                        true);
                }

                int remainingMilliseconds = Math.Max(
                    1,
                    timeoutMilliseconds - (int)Math.Min(stopwatch.ElapsedMilliseconds, timeoutMilliseconds));
                var drainTasks = new Task[] { outputTask, errorTask };
                if (!Task.WaitAll(drainTasks, remainingMilliseconds))
                {
                    TryTerminateProcessTree(process);
                    return new GitCommandResult(
                        -1,
                        GetCompletedOutput(outputTask),
                        GetCompletedOutput(errorTask),
                        true);
                }

                string output = outputTask.GetAwaiter().GetResult();
                string error = errorTask.GetAwaiter().GetResult();
                return new GitCommandResult(process.ExitCode, output, error, false);
            }
        }

        private static string GetCompletedOutput(Task<string> task)
        {
            if (task == null || !task.IsCompleted) return "";

            try
            {
                return task.GetAwaiter().GetResult();
            }
            catch
            {
                return "";
            }
        }

        private static void TryTerminateProcessTree(Process process)
        {
            if (process == null) return;

#if UNITY_EDITOR_WIN
            try
            {
                var taskKillInfo = new ProcessStartInfo
                {
                    FileName = "taskkill",
                    Arguments = $"/PID {process.Id} /T /F",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using (var taskKill = Process.Start(taskKillInfo))
                {
                    bool taskKillFinished = taskKill?.WaitForExit(TerminationWaitMilliseconds) ?? false;
                    if (!taskKillFinished || taskKill.ExitCode != 0)
                        TryKillProcess(process);
                }
            }
            catch
            {
                TryKillProcess(process);
            }
#else
            TryKillProcess(process);
#endif

            try
            {
                process.WaitForExit(TerminationWaitMilliseconds);
            }
            catch
            {
                // The original timeout remains the actionable error.
            }
        }

        private static void TryKillProcess(Process process)
        {
            try
            {
                if (!process.HasExited) process.Kill();
            }
            catch
            {
                // The original timeout remains the actionable error.
            }
        }
    }

    internal static class BuildSettingBridge
    {
        internal const string PackageId = "com.actionfit.buildsetting";
        internal const string MinimumVersion = "1.1.11";
        internal const string BuildSettingsTypeName = "ActionFit.BuildSetting.Editor.BuildSettingsSO, com.actionfit.buildsetting.Editor";

        private const string BuildSettingsApplierTypeName = "ActionFit.BuildSetting.Editor.BuildSettingsApplier, com.actionfit.buildsetting.Editor";
        private const string AndroidBuildProcessTypeName = "ActionFit.BuildSetting.Editor.AOSBuildProcess, com.actionfit.buildsetting.Editor";
        private const string IosBuildProcessTypeName = "ActionFit.BuildSetting.Editor.iOSBuildProcess, com.actionfit.buildsetting.Editor";
        private const string FallbackSOPrefsKey = "LastUsedBuildSettings";

        internal static Type SettingsType => Type.GetType(BuildSettingsTypeName);

        internal static string SOPrefsKey
        {
            get
            {
                FieldInfo field = SettingsType?.GetField("SOPrefsKey", BindingFlags.Public | BindingFlags.Static);
                return field?.GetValue(null) as string ?? FallbackSOPrefsKey;
            }
        }

        internal static bool IsAvailable()
        {
            return HasRequiredContract(SettingsType);
        }

        internal static bool HasRequiredContract(Type settingsType)
        {
            FieldInfo developmentBuildField = settingsType?.GetField(
                "developmentBuild",
                BindingFlags.Public | BindingFlags.Instance);
            return developmentBuildField?.FieldType == typeof(bool);
        }

        internal static bool EnsureAvailable(bool showDialog)
        {
            if (IsAvailable())
                return true;

            if (showDialog)
            {
                EditorUtility.DisplayDialog(
                    "Build Setting Required",
                    $"Build Automation requires `{PackageId}@{MinimumVersion}`.\n\n" +
                    "Install or update Build Automation through ActionFit Package Manager so catalog dependencies are written to the project manifest, then reopen Unity after Package Manager resolves.",
                    "OK");
            }

            return false;
        }

        internal static ScriptableObject FindSettingsAsset()
        {
            return InvokeStaticSettingsMethod("FindSettingsAsset") as ScriptableObject;
        }

        internal static ScriptableObject FindOrCreateSettingsAsset()
        {
            return InvokeStaticSettingsMethod("FindOrCreateSettingsAsset") as ScriptableObject;
        }

        internal static void ApplyVersionSettings(ScriptableObject settings)
        {
            Type type = Type.GetType(BuildSettingsApplierTypeName);
            MethodInfo method = type?.GetMethod("ApplyVersionSettings", BindingFlags.Public | BindingFlags.Static);
            method?.Invoke(null, new object[] { settings });
        }

        internal static BuildReport BuildAndroidForCI(ScriptableObject settings, bool aab)
        {
            Type type = Type.GetType(AndroidBuildProcessTypeName);
            MethodInfo method = type?.GetMethod("BuildForCI", BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, new object[] { settings, aab }) as BuildReport;
        }

        internal static BuildReport BuildIosForCI(ScriptableObject settings)
        {
            Type type = Type.GetType(IosBuildProcessTypeName);
            MethodInfo method = type?.GetMethod("BuildForCI", BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, new object[] { settings }) as BuildReport;
        }

        internal static string GetString(ScriptableObject settings, string fieldName)
        {
            object value = GetFieldValue(settings, fieldName);
            return value as string ?? "";
        }

        internal static bool TryGetBool(ScriptableObject settings, string fieldName, out bool value)
        {
            object fieldValue = GetFieldValue(settings, fieldName);
            if (fieldValue is bool boolValue)
            {
                value = boolValue;
                return true;
            }

            value = false;
            return false;
        }

        internal static void SetString(ScriptableObject settings, string fieldName, string value)
        {
            SetFieldValue(settings, fieldName, value ?? "");
        }

        internal static bool SetBool(ScriptableObject settings, string fieldName, bool value)
        {
            return SetFieldValue(settings, fieldName, value);
        }

        private static object InvokeStaticSettingsMethod(string methodName)
        {
            Type type = SettingsType;
            MethodInfo method = type?.GetMethod(methodName, BindingFlags.Public | BindingFlags.Static);
            return method?.Invoke(null, null);
        }

        private static object GetFieldValue(ScriptableObject settings, string fieldName)
        {
            if (settings == null || string.IsNullOrEmpty(fieldName))
                return null;

            FieldInfo field = settings.GetType().GetField(fieldName, BindingFlags.Public | BindingFlags.Instance);
            return field?.GetValue(settings);
        }

        private static bool SetFieldValue(ScriptableObject settings, string fieldName, object value)
        {
            if (settings == null || string.IsNullOrEmpty(fieldName))
                return false;

            FieldInfo field = settings.GetType().GetField(fieldName, BindingFlags.Public | BindingFlags.Instance);
            if (field == null || value == null || !field.FieldType.IsInstanceOfType(value))
                return false;

            field?.SetValue(settings, value);
            return true;
        }
    }

    internal static class CustomSymbolsBridge
    {
        internal const string PackageId = "com.actionfit.customsymbols";
        internal const string MinimumVersion = "1.0.6";

        private const string SettingsTypeName = "CustomSymbolsSO, com.actionfit.customsymbols.Editor";
        private const string WindowTypeName = "SymbolsWindow, com.actionfit.customsymbols.Editor";
        private const string WindowMenuPath = "Tools/Package/Custom Symbols/Open Window";

        private static bool _availabilityResolved;
        private static string _availabilityError;
        private static Type SettingsType => Type.GetType(SettingsTypeName);

        internal static bool IsAvailable()
        {
            return TryEnsureAvailable(out _);
        }

        internal static bool TryEnsureAvailable(out string error)
        {
            if (!_availabilityResolved)
            {
                _availabilityError = ResolveAvailabilityError();
                _availabilityResolved = true;
            }

            error = _availabilityError;
            return string.IsNullOrEmpty(error);
        }

        internal static bool OpenWindow()
        {
            if (!TryEnsureAvailable(out string availabilityError))
            {
                Debug.LogError($"[BuildAutomation] {availabilityError}");
                return false;
            }

            if (EditorApplication.ExecuteMenuItem(WindowMenuPath))
                return true;

            Type windowType = Type.GetType(WindowTypeName);
            MethodInfo showMethod = windowType?.GetMethod("ShowWindow", BindingFlags.Public | BindingFlags.Static);
            if (showMethod == null)
            {
                Debug.LogError($"[BuildAutomation] Custom Symbols window is unavailable. Update {PackageId} to {MinimumVersion} or newer.");
                return false;
            }

            showMethod.Invoke(null, null);
            return true;
        }

        internal static bool HasSettingsAsset()
        {
            return TryEnsureAvailable(out _) && FindSettingsAsset() != null;
        }

        internal static bool TryApplyBuildSymbols(BuildTarget target, out string error)
        {
            if (!TryGetBuildSymbols(target, out string[] buildSymbols, out error))
                return false;

            var namedTarget = NamedBuildTarget.FromBuildTargetGroup(BuildPipeline.GetBuildTargetGroup(target));
            PlayerSettings.GetScriptingDefineSymbols(namedTarget, out string[] currentSymbols);
            if (SymbolSetsMatch(currentSymbols, buildSymbols))
            {
                Debug.Log($"[BuildAutomation] Custom Symbols already prepared for {target}: {FormatSymbols(buildSymbols)}");
                return true;
            }

            PlayerSettings.SetScriptingDefineSymbols(namedTarget, buildSymbols);
            AssetDatabase.SaveAssets();
            Debug.Log($"[BuildAutomation] Prepared Custom Symbols for next Unity process ({target}): {FormatSymbols(buildSymbols)}");
            return true;
        }

        internal static bool TryValidateBuildSymbols(BuildTarget target, out string error)
        {
            if (!TryGetBuildSymbols(target, out string[] expectedSymbols, out error))
                return false;

            var namedTarget = NamedBuildTarget.FromBuildTargetGroup(BuildPipeline.GetBuildTargetGroup(target));
            PlayerSettings.GetScriptingDefineSymbols(namedTarget, out string[] currentSymbols);
            if (SymbolSetsMatch(currentSymbols, expectedSymbols))
            {
                Debug.Log($"[BuildAutomation] Custom Symbols verified for {target}: {FormatSymbols(expectedSymbols)}");
                return true;
            }

            var expected = new HashSet<string>(expectedSymbols, StringComparer.Ordinal);
            var current = new HashSet<string>(currentSymbols ?? Array.Empty<string>(), StringComparer.Ordinal);
            string missing = FormatSymbols(expected.Where(symbol => !current.Contains(symbol)));
            string extra = FormatSymbols(current.Where(symbol => !expected.Contains(symbol)));
            error = $"Custom Symbols mismatch for {target}. Missing: {missing}. Extra: {extra}. " +
                    "Run SwitchToRequestBuildTarget before BuildFromRequest.";
            return false;
        }

        private static bool TryGetBuildSymbols(BuildTarget target, out string[] buildSymbols, out string error)
        {
            buildSymbols = Array.Empty<string>();
            error = null;

            if (!TryEnsureAvailable(out error))
                return false;

            Type settingsType = SettingsType;
            ScriptableObject settings = FindSettingsAsset();
            if (settings == null)
            {
                error = "CustomSymbolsSO could not be found or created. Check the default settings path and Unity Console.";
                return false;
            }

            MethodInfo getBuildSymbols = settingsType.GetMethod(
                "GetBuildSymbols",
                BindingFlags.Public | BindingFlags.Instance,
                null,
                new[] { typeof(BuildTarget) },
                null);
            if (getBuildSymbols == null)
            {
                error = $"{PackageId} does not expose GetBuildSymbols(BuildTarget). Update it to {MinimumVersion} or newer.";
                return false;
            }

            var values = getBuildSymbols.Invoke(settings, new object[] { target }) as IEnumerable<string>;
            if (values == null)
            {
                error = $"Custom Symbols returned no build symbol list for {target}.";
                return false;
            }

            buildSymbols = values
                .Select(symbol => symbol?.Trim())
                .Where(symbol => !string.IsNullOrEmpty(symbol))
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            return true;
        }

        private static ScriptableObject FindSettingsAsset()
        {
            Type settingsType = SettingsType;
            MethodInfo findMethod = settingsType?.GetMethod("FindOrCreateSettingsAsset", BindingFlags.Public | BindingFlags.Static);
            var settings = findMethod?.Invoke(null, null) as ScriptableObject;
            if (settings != null) return settings;

            string[] guids = AssetDatabase.FindAssets("t:CustomSymbolsSO");
            if (guids.Length == 0 || settingsType == null) return null;

            string path = AssetDatabase.GUIDToAssetPath(guids[0]);
            return AssetDatabase.LoadAssetAtPath(path, settingsType) as ScriptableObject;
        }

        private static string ResolveAvailabilityError()
        {
            Type settingsType = SettingsType;
            if (settingsType == null)
                return $"Custom Symbols package is unavailable. Install {PackageId}@{MinimumVersion} or newer.";

            UnityEditor.PackageManager.PackageInfo packageInfo =
                UnityEditor.PackageManager.PackageInfo.FindForAssembly(settingsType.Assembly);
            string installedVersion = packageInfo?.version;
            if (string.IsNullOrWhiteSpace(installedVersion))
                return $"Custom Symbols package version could not be resolved. Install {PackageId}@{MinimumVersion} or newer.";

            if (!IsVersionAtLeast(installedVersion, MinimumVersion))
            {
                return $"Custom Symbols {installedVersion} is too old for batchmode AutoBuild. " +
                       $"Install {PackageId}@{MinimumVersion} or newer.";
            }

            return null;
        }

        internal static bool IsVersionAtLeast(string installedVersion, string minimumVersion)
        {
            string installedWithoutBuild = installedVersion.Split('+')[0];
            string minimumWithoutBuild = minimumVersion.Split('+')[0];
            string installedCore = installedWithoutBuild.Split('-')[0];
            string minimumCore = minimumWithoutBuild.Split('-')[0];
            if (!Version.TryParse(installedCore, out Version installed) ||
                !Version.TryParse(minimumCore, out Version minimum))
            {
                return false;
            }

            int coreComparison = installed.CompareTo(minimum);
            if (coreComparison != 0)
                return coreComparison > 0;

            bool installedIsPrerelease = installedWithoutBuild.Contains("-");
            bool minimumIsPrerelease = minimumWithoutBuild.Contains("-");
            return minimumIsPrerelease || !installedIsPrerelease;
        }

        private static bool SymbolSetsMatch(IEnumerable<string> left, IEnumerable<string> right)
        {
            var leftSet = new HashSet<string>(left ?? Array.Empty<string>(), StringComparer.Ordinal);
            var rightSet = new HashSet<string>(right ?? Array.Empty<string>(), StringComparer.Ordinal);
            return leftSet.SetEquals(rightSet);
        }

        private static string FormatSymbols(IEnumerable<string> symbols)
        {
            string[] values = symbols?.Where(symbol => !string.IsNullOrEmpty(symbol)).ToArray() ?? Array.Empty<string>();
            return values.Length == 0 ? "(none)" : string.Join(", ", values);
        }
    }
}

#endif
