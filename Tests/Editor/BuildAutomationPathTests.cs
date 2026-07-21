#if UNITY_EDITOR

using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
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

        [Test]
        [Timeout(30000)]
        public void RunWithIndexLockRetrySucceedsAfterLockIsReleased()
        {
            string testRoot = Path.Combine(
                Path.GetTempPath(),
                "ActionFitBuildAutomationTests",
                Guid.NewGuid().ToString("N"),
                "git-index-lock-retry");
            Directory.CreateDirectory(testRoot);

            try
            {
                GitCommandResult initResult = GitProcessRunner.Run(testRoot, "init", 10000);
                Assert.That(initResult.ExitCode, Is.EqualTo(0), initResult.Error);

                File.WriteAllText(Path.Combine(testRoot, "request.txt"), "request");
                string lockPath = Path.Combine(testRoot, ".git", "index.lock");
                File.WriteAllText(lockPath, "busy");

                Task releaseLockTask = Task.Run(async () =>
                {
                    await Task.Delay(150);
                    File.Delete(lockPath);
                });

                GitCommandResult addResult = GitProcessRunner.RunWithIndexLockRetry(
                    testRoot,
                    "add request.txt",
                    10000,
                    20,
                    25);

                Assert.That(releaseLockTask.Wait(1000), Is.True);
                Assert.That(addResult.TimedOut, Is.False);
                Assert.That(addResult.ExitCode, Is.EqualTo(0), addResult.Error);
                Assert.That(addResult.IndexLockRetryCount, Is.GreaterThan(0));
                Assert.That(File.Exists(lockPath), Is.False);
            }
            finally
            {
                string operationRoot = Directory.GetParent(testRoot)?.FullName;
                if (!string.IsNullOrWhiteSpace(operationRoot) && Directory.Exists(operationRoot))
                    DeleteDirectory(operationRoot);
            }
        }

        [Test]
        [Timeout(30000)]
        public void RunWithIndexLockRetryLeavesPersistentLockUntouched()
        {
            string testRoot = Path.Combine(
                Path.GetTempPath(),
                "ActionFitBuildAutomationTests",
                Guid.NewGuid().ToString("N"),
                "git-index-lock-persistent");
            Directory.CreateDirectory(testRoot);

            try
            {
                GitCommandResult initResult = GitProcessRunner.Run(testRoot, "init", 10000);
                Assert.That(initResult.ExitCode, Is.EqualTo(0), initResult.Error);

                File.WriteAllText(Path.Combine(testRoot, "request.txt"), "request");
                string lockPath = Path.Combine(testRoot, ".git", "index.lock");
                File.WriteAllText(lockPath, "busy");

                GitCommandResult addResult = GitProcessRunner.RunWithIndexLockRetry(
                    testRoot,
                    "add request.txt",
                    10000,
                    2,
                    1);

                Assert.That(addResult.TimedOut, Is.False);
                Assert.That(addResult.ExitCode, Is.Not.EqualTo(0));
                Assert.That(addResult.IndexLockRetryCount, Is.EqualTo(2));
                Assert.That(GitProcessRunner.IsIndexLockContention(addResult), Is.True);
                Assert.That(File.Exists(lockPath), Is.True);
            }
            finally
            {
                string operationRoot = Directory.GetParent(testRoot)?.FullName;
                if (!string.IsNullOrWhiteSpace(operationRoot) && Directory.Exists(operationRoot))
                    DeleteDirectory(operationRoot);
            }
        }

        [Test]
        [Timeout(60000)]
        public void AndroidBuildNumberReservationIsUniqueAcrossConcurrentBranches()
        {
            string operationRoot = Path.Combine(
                Path.GetTempPath(),
                "ActionFitBuildAutomationTests",
                Guid.NewGuid().ToString("N"),
                "android-build-number-reservation");
            string remoteRoot = Path.Combine(operationRoot, "remote.git");
            string firstRoot = Path.Combine(operationRoot, "first");
            string secondRoot = Path.Combine(operationRoot, "second");
            Directory.CreateDirectory(operationRoot);

            try
            {
                AssertGit(operationRoot, $"init --bare \"{remoteRoot}\"");
                AssertGit(operationRoot, $"clone \"{remoteRoot}\" \"{firstRoot}\"");
                ConfigureGitIdentity(firstRoot);
                File.WriteAllText(Path.Combine(firstRoot, "request.txt"), "initial");
                AssertGit(firstRoot, "add request.txt");
                AssertGit(firstRoot, "commit -m initial");
                AssertGit(firstRoot, "push origin HEAD:main");
                AssertGit(operationRoot, $"clone --branch main \"{remoteRoot}\" \"{secondRoot}\"");
                ConfigureGitIdentity(secondRoot);

                var numbers = new string[2];
                var tags = new string[2];
                var errors = new string[2];
                var successes = new bool[2];
                Task firstTask = Task.Run(() =>
                {
                    successes[0] = AndroidBuildNumberReservation.TryReserve(
                        firstRoot,
                        "568",
                        out numbers[0],
                        out tags[0],
                        out _,
                        out errors[0]);
                });
                Task secondTask = Task.Run(() =>
                {
                    successes[1] = AndroidBuildNumberReservation.TryReserve(
                        secondRoot,
                        "568",
                        out numbers[1],
                        out tags[1],
                        out _,
                        out errors[1]);
                });

                Assert.That(Task.WaitAll(new[] { firstTask, secondTask }, 30000), Is.True);
                Assert.That(successes[0], Is.True, errors[0]);
                Assert.That(successes[1], Is.True, errors[1]);
                Assert.That(numbers, Is.EquivalentTo(new[] { "569", "570" }));
                Assert.That(tags, Is.EquivalentTo(new[]
                {
                    "build-number/android/569",
                    "build-number/android/570"
                }));

                GitCommandResult remoteTags = GitProcessRunner.Run(
                    firstRoot,
                    "ls-remote --tags origin \"refs/tags/build-number/android/*\"",
                    10000);
                Assert.That(remoteTags.ExitCode, Is.EqualTo(0), remoteTags.Error);
                Assert.That(remoteTags.Output, Does.Contain("refs/tags/build-number/android/569"));
                Assert.That(remoteTags.Output, Does.Contain("refs/tags/build-number/android/570"));
            }
            finally
            {
                if (Directory.Exists(operationRoot))
                    DeleteDirectory(operationRoot);
            }
        }

        private static void ConfigureGitIdentity(string repositoryRoot)
        {
            AssertGit(repositoryRoot, "config user.name ActionFitBuildAutomationTests");
            AssertGit(repositoryRoot, "config user.email buildautomation-tests@actionfit.local");
        }

        private static void AssertGit(string workingDirectory, string arguments)
        {
            GitCommandResult result = GitProcessRunner.Run(workingDirectory, arguments, 10000);
            Assert.That(result.TimedOut, Is.False, $"git {arguments} timed out");
            Assert.That(result.ExitCode, Is.EqualTo(0), result.Error);
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
