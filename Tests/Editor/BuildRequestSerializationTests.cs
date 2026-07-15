#if UNITY_EDITOR

using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildRequestSerializationTests
    {
        [Test]
        public void Schema12RoundTripsDevelopmentBuildProjectSymbolsAndAndroidSigning()
        {
            var request = new BuildRequest
            {
                unityProjectPath = "KnitFactory",
                autoConfigureBuildSymbols = true,
                developmentBuild = true,
                androidKeystoreFileName = "upload.keystore",
                androidKeystoreBase64 = "dGVzdC1rZXlzdG9yZQ==",
                androidKeystorePassword = "request-keystore-pass",
                androidAliasPassword = "request-alias-pass"
            };

            string json = JsonUtility.ToJson(request);
            BuildRequest restored = JsonUtility.FromJson<BuildRequest>(json);

            Assert.That(request.schemaVersion, Is.EqualTo(BuildRequest.CurrentSchemaVersion));
            Assert.That(request.schemaVersion, Is.EqualTo(12));
            Assert.That(restored.unityProjectPath, Is.EqualTo("KnitFactory"));
            Assert.That(restored.autoConfigureBuildSymbols, Is.True);
            Assert.That(restored.developmentBuild, Is.True);
            Assert.That(restored.androidKeystoreFileName, Is.EqualTo("upload.keystore"));
            Assert.That(restored.androidKeystoreBase64, Is.EqualTo("dGVzdC1rZXlzdG9yZQ=="));
            Assert.That(restored.androidKeystorePassword, Is.EqualTo("request-keystore-pass"));
            Assert.That(restored.androidAliasPassword, Is.EqualTo("request-alias-pass"));
        }

        [Test]
        public void BuildSettingBridgeRequiresDevelopmentBuildBoolField()
        {
            Assert.That(BuildSettingBridge.HasRequiredContract(typeof(CompatibleBuildSettings)), Is.True);
            Assert.That(BuildSettingBridge.HasRequiredContract(typeof(MissingDevelopmentBuildSettings)), Is.False);
            Assert.That(BuildSettingBridge.HasRequiredContract(null), Is.False);

            var settings = ScriptableObject.CreateInstance<CompatibleBuildSettings>();
            try
            {
                settings.developmentBuild = true;
                Assert.That(BuildSettingBridge.TryGetBool(settings, "developmentBuild", out bool value), Is.True);
                Assert.That(value, Is.True);
            }
            finally
            {
                Object.DestroyImmediate(settings);
            }
        }

        [Test]
        public void ApplyRequestWritesDevelopmentBuildAndRejectsMissingContract()
        {
            var compatible = ScriptableObject.CreateInstance<CompatibleBuildSettings>();
            var incompatible = ScriptableObject.CreateInstance<MissingDevelopmentBuildSettings>();
            var request = new BuildRequest { developmentBuild = true };

            try
            {
                Assert.That(CIBuildEntry.ApplyRequest(compatible, request), Is.True);
                Assert.That(compatible.developmentBuild, Is.True);
                LogAssert.Expect(
                    LogType.Error,
                    "[CIBuildEntry] BuildSettingsSO does not support developmentBuild. Update com.actionfit.buildsetting to 1.1.11 or newer.");
                Assert.That(CIBuildEntry.ApplyRequest(incompatible, request), Is.False);
            }
            finally
            {
                Object.DestroyImmediate(compatible);
                Object.DestroyImmediate(incompatible);
            }
        }

        [Test]
        public void CustomSymbolsDependencyMeetsBatchmodeMinimumVersion()
        {
            Assert.That(
                CustomSymbolsBridge.TryEnsureAvailable(out string error),
                Is.True,
                error);
        }

        [Test]
        public void CustomSymbolsSettingsCanBeFoundOrCreated()
        {
            Assert.That(CustomSymbolsBridge.HasSettingsAsset(), Is.True);
        }

        [TestCase("1.0.5-preview.1", false)]
        [TestCase("1.0.5", false)]
        [TestCase("1.0.6-preview.1", false)]
        [TestCase("1.0.6", true)]
        [TestCase("1.0.7-preview.1", true)]
        public void CustomSymbolsMinimumVersionUsesStableSemverBoundary(
            string installedVersion,
            bool expected)
        {
            Assert.That(
                CustomSymbolsBridge.IsVersionAtLeast(installedVersion, "1.0.6"),
                Is.EqualTo(expected));
        }

        private sealed class CompatibleBuildSettings : ScriptableObject
        {
            public bool developmentBuild;
            public bool saveFileInProject;
            public bool manageSymbolsOnBuild;
        }

        private sealed class MissingDevelopmentBuildSettings : ScriptableObject
        {
        }
    }
}

#endif
