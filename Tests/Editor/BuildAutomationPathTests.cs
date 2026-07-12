#if UNITY_EDITOR

using System;
using System.IO;
using System.Text;
using NUnit.Framework;

namespace ActionFit.BuildAutomation.Editor.Tests
{
    public class BuildAutomationPathTests
    {
        [Test]
        public void RootUnityProjectUsesDotPath()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/repo",
                out string unityProjectPath,
                out string error);

            Assert.That(resolved, Is.True, error);
            Assert.That(unityProjectPath, Is.EqualTo("."));
        }

        [Test]
        public void NestedUnityProjectUsesRepositoryRelativePath()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/repo/KnitFactory",
                out string unityProjectPath,
                out string error);

            Assert.That(resolved, Is.True, error);
            Assert.That(unityProjectPath, Is.EqualTo("KnitFactory"));
        }

        [Test]
        public void UnityProjectOutsideRepositoryIsRejected()
        {
            bool resolved = BuildAutomationProjectPaths.TryGetUnityProjectPath(
                "/repo",
                "/other/KnitFactory",
                out _,
                out string error);

            Assert.That(resolved, Is.False);
            Assert.That(error, Does.Contain("escapes the repository"));
        }

        [TestCase("../KnitFactory")]
        [TestCase("Games/../../KnitFactory")]
        [TestCase("/absolute/KnitFactory")]
        public void UnsafeUnityProjectPathIsRejected(string value)
        {
            bool normalized = BuildAutomationProjectPaths.TryNormalizeUnityProjectPath(
                value,
                out _,
                out _);

            Assert.That(normalized, Is.False);
        }
    }

    public class GitProcessRunnerTests
    {
        [Test]
        [Timeout(30000)]
        public void RunDrainsLargeLineEndingWarningsWithoutDeadlock()
        {
            string testRoot = Path.Combine(
                Path.GetTempPath(),
                "ActionFitBuildAutomationTests",
                Guid.NewGuid().ToString("N"),
                "git-output-drain");
            Directory.CreateDirectory(testRoot);

            try
            {
                GitCommandResult initResult = GitProcessRunner.Run(testRoot, "init", 10000);
                Assert.That(initResult.TimedOut, Is.False);
                Assert.That(initResult.ExitCode, Is.EqualTo(0), initResult.Error);

                var utf8WithoutBom = new UTF8Encoding(false);
                for (int i = 0; i < 512; i++)
                {
                    string path = Path.Combine(testRoot, $"line-ending-{i:D4}.txt");
                    File.WriteAllText(path, "first line\nsecond line\n", utf8WithoutBom);
                }

                GitCommandResult addResult = GitProcessRunner.Run(
                    testRoot,
                    "-c core.autocrlf=true -c core.safecrlf=warn add -A",
                    10000);

                Assert.That(addResult.TimedOut, Is.False);
                Assert.That(addResult.ExitCode, Is.EqualTo(0), addResult.Error);
                Assert.That(File.Exists(Path.Combine(testRoot, ".git", "index.lock")), Is.False);
            }
            finally
            {
                string operationRoot = Directory.GetParent(testRoot)?.FullName;
                if (!string.IsNullOrWhiteSpace(operationRoot) && Directory.Exists(operationRoot))
                    DeleteDirectory(operationRoot);
            }
        }

        private static void DeleteDirectory(string path)
        {
            foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
                File.SetAttributes(file, FileAttributes.Normal);
            foreach (string directory in Directory.GetDirectories(path, "*", SearchOption.AllDirectories))
                File.SetAttributes(directory, FileAttributes.Directory);
            File.SetAttributes(path, FileAttributes.Directory);
            Directory.Delete(path, true);
        }
    }
}

#endif
