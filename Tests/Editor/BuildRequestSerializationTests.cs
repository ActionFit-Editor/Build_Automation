#if UNITY_EDITOR

using NUnit.Framework;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildRequestSerializationTests
    {
        [Test]
        public void Schema11RoundTripsProjectSymbolsAndAndroidSigning()
        {
            var request = new BuildRequest
            {
                unityProjectPath = "KnitFactory",
                autoConfigureBuildSymbols = true,
                androidKeystoreFileName = "upload.keystore",
                androidKeystoreBase64 = "dGVzdC1rZXlzdG9yZQ==",
                androidKeystorePassword = "request-keystore-pass",
                androidAliasPassword = "request-alias-pass"
            };

            string json = JsonUtility.ToJson(request);
            BuildRequest restored = JsonUtility.FromJson<BuildRequest>(json);

            Assert.That(request.schemaVersion, Is.EqualTo(11));
            Assert.That(restored.unityProjectPath, Is.EqualTo("KnitFactory"));
            Assert.That(restored.autoConfigureBuildSymbols, Is.True);
            Assert.That(restored.androidKeystoreFileName, Is.EqualTo("upload.keystore"));
            Assert.That(restored.androidKeystoreBase64, Is.EqualTo("dGVzdC1rZXlzdG9yZQ=="));
            Assert.That(restored.androidKeystorePassword, Is.EqualTo("request-keystore-pass"));
            Assert.That(restored.androidAliasPassword, Is.EqualTo("request-alias-pass"));
        }

        [Test]
        public void CustomSymbolsDependencyMeetsBatchmodeMinimumVersion()
        {
            Assert.That(
                CustomSymbolsBridge.TryEnsureAvailable(out string error),
                Is.True,
                error);
        }

        [TestCase("1.0.4", false)]
        [TestCase("1.0.5-preview.1", false)]
        [TestCase("1.0.5", true)]
        [TestCase("1.0.6-preview.1", true)]
        public void CustomSymbolsMinimumVersionUsesStableSemverBoundary(
            string installedVersion,
            bool expected)
        {
            Assert.That(
                CustomSymbolsBridge.IsVersionAtLeast(installedVersion, "1.0.5"),
                Is.EqualTo(expected));
        }
    }
}

#endif
