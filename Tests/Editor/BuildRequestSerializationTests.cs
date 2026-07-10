#if UNITY_EDITOR

using NUnit.Framework;
using UnityEngine;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildRequestSerializationTests
    {
        private static readonly string[] ForbiddenCredentialFields =
        {
            "androidKeystoreFileName",
            "androidKeystoreBase64",
            "androidKeystorePassword",
            "androidAliasPassword",
            "iosDevelopmentTeamId",
            "googlePlayServiceAccountJson",
            "appStoreConnectApiKeyId",
            "appStoreConnectIssuerId",
            "appStoreConnectApiKeyP8"
        };

        [Test]
        public void Schema11ContainsProjectAndSymbolSettingsWithoutCredentials()
        {
            var request = new BuildRequest
            {
                unityProjectPath = "KnitFactory",
                autoConfigureBuildSymbols = true
            };

            string json = JsonUtility.ToJson(request);

            Assert.That(request.schemaVersion, Is.EqualTo(11));
            Assert.That(json, Does.Contain("\"unityProjectPath\":\"KnitFactory\""));
            Assert.That(json, Does.Contain("\"autoConfigureBuildSymbols\":true"));
            foreach (string field in ForbiddenCredentialFields)
            {
                Assert.That(json, Does.Not.Contain(field));
                Assert.That(typeof(BuildRequest).GetField(field), Is.Null);
            }
        }

        [Test]
        public void LegacyCredentialFieldsAreIgnoredDuringDeserialization()
        {
            const string legacyJson =
                "{\"schemaVersion\":10,\"triggerSource\":\"BuildCommit\"," +
                "\"androidKeystoreBase64\":\"legacy-secret\"," +
                "\"androidKeystorePassword\":\"legacy-password\"}";

            BuildRequest request = JsonUtility.FromJson<BuildRequest>(legacyJson);
            string serialized = JsonUtility.ToJson(request);

            Assert.That(request.triggerSource, Is.EqualTo(BuildRequest.BuildCommitTriggerSource));
            Assert.That(serialized, Does.Not.Contain("legacy-secret"));
            Assert.That(serialized, Does.Not.Contain("legacy-password"));
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
