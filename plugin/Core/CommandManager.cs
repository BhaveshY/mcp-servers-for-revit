using Autodesk.Revit.UI;
using RevitMCPSDK.API.Interfaces;
using RevitMCPSDK.API.Utils;
using revit_mcp_plugin.Configuration;
using revit_mcp_plugin.Utils;
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace revit_mcp_plugin.Core
{
    /// <summary>
    /// <para>命令管理器，负责加载和管理命令</para>
    /// <para>Command Manager</para>
    /// </summary>
    public class CommandManager
    {
        private readonly ICommandRegistry _commandRegistry;
        private readonly ILogger _logger;
        private readonly ConfigurationManager _configManager;
        private readonly UIApplication _uiApplication;
        private readonly RevitVersionAdapter _versionAdapter;
        private readonly List<string> _loadedCommands = new List<string>();
        private readonly Dictionary<string, string> _failedCommands = new Dictionary<string, string>();

        /// <summary>Names of commands that registered successfully on the last LoadCommands() call.</summary>
        public IReadOnlyList<string> LoadedCommands => _loadedCommands;

        /// <summary>Map of failed command name -> short error description from the last LoadCommands() call.</summary>
        public IReadOnlyDictionary<string, string> FailedCommands => _failedCommands;

        /// <summary>
        /// Manager in charge of loading and managing commands.
        /// </summary>
        /// <param name="commandRegistry"></param>
        /// <param name="logger"></param>
        /// <param name="configManager"></param>
        /// <param name="uiApplication"></param>
        public CommandManager(
            ICommandRegistry commandRegistry,
            ILogger logger,
            ConfigurationManager configManager,
            UIApplication uiApplication)
        {
            _commandRegistry = commandRegistry;
            _logger = logger;
            _configManager = configManager;
            _uiApplication = uiApplication;
            _versionAdapter = new RevitVersionAdapter(_uiApplication.Application);
        }

        /// <summary>
        /// <para>加载配置文件中指定的所有命令.</para>
        /// <para>Load all commands specified in the configuration file.</para>
        /// </summary>
        public void LoadCommands()
        {
            _loadedCommands.Clear();
            _failedCommands.Clear();
            _logger.Info("开始加载命令\nStart loading command.");
            string currentVersion = _versionAdapter.GetRevitVersion();
            _logger.Info("当前 Revit 版本: {0}\nCurrent Revit version: {0}", currentVersion);

            // 从配置加载外部命令
            // Load external commands from the configuration file.
            foreach (var commandConfig in _configManager.Config.Commands)
            {
                try
                {
                    if (!commandConfig.Enabled)
                    {
                        _logger.Info("跳过禁用的命令: {0}\nSkipping disabled command: {0}", commandConfig.CommandName);
                        continue;
                    }

                    // 检查版本兼容性
                    // Check Revit version compatibility.
                    if (commandConfig.SupportedRevitVersions != null &&
                        commandConfig.SupportedRevitVersions.Length > 0 &&
                        !_versionAdapter.IsVersionSupported(commandConfig.SupportedRevitVersions))
                    {
                        _logger.Warning("命令 {0} 不支持当前 Revit 版本 {1}，已跳过\nThe command {0} is not supported by the current Revit version ({1}} and it has been skipped.",
                            commandConfig.CommandName, currentVersion);
                        continue;
                    }

                    // 替换路径中的版本占位符
                    // Replace version placeholder strings in paths.
                    commandConfig.AssemblyPath = commandConfig.AssemblyPath.Contains("{VERSION}")
                        ? commandConfig.AssemblyPath.Replace("{VERSION}", currentVersion)
                        : commandConfig.AssemblyPath;

                    // 加载外部命令程序集
                    // Load external command assembly.
                    LoadCommandFromAssembly(commandConfig);
                }
                catch (Exception ex)
                {
                    _failedCommands[commandConfig.CommandName] = ex.GetType().Name + ": " + ex.Message;
                    _logger.Error(
                        "加载命令 {0} 失败: {1}: {2}\nFailed to load command {0}: {1}: {2}",
                        commandConfig.CommandName, ex.GetType().FullName, ex.Message);
                    for (var inner = ex.InnerException; inner != null; inner = inner.InnerException)
                    {
                        _logger.Error("  -> Inner: {0}: {1}", inner.GetType().FullName, inner.Message);
                    }
                }
            }

            _logger.Info(
                "命令加载完成: {0} 成功, {1} 失败\nCommand loading complete: {0} loaded, {1} failed.",
                _loadedCommands.Count, _failedCommands.Count);
        }

        /// <summary>
        /// 加载特定程序集中的特定命令
        /// Loads specific commands in specific assemblies.
        /// </summary>
        /// <param name="config">Configuration class describing the command.</param>
        private void LoadCommandFromAssembly(CommandConfig config)
        {
            try
            {
                // 确定程序集路径
                // Determine the assembly path.
                string assemblyPath = config.AssemblyPath;
                if (!Path.IsPathRooted(assemblyPath))
                {
                    // 如果不是绝对路径，则相对于Commands目录
                    // If it is not an absolute path, then it is relative to the Command's directory.
                    string baseDir = PathManager.GetCommandsDirectoryPath();
                    assemblyPath = Path.Combine(baseDir, assemblyPath);
                }

                if (!File.Exists(assemblyPath))
                {
                    _logger.Error("命令程序集不存在: {0}\nCommand assembly does not exist: {0}", assemblyPath);
                    return;
                }

                // 加载程序集
                // Load assembly.
                Assembly assembly = Assembly.LoadFrom(assemblyPath);

                // 查找实现 IRevitCommand 接口的类型
                // Find types that implement the IRevitCommand interface.
                foreach (Type type in assembly.GetTypes())
                {
                    if (typeof(RevitMCPSDK.API.Interfaces.IRevitCommand).IsAssignableFrom(type) &&
                        !type.IsInterface &&
                        !type.IsAbstract)
                    {
                        try
                        {
                            // 创建命令实例
                            // Create a command instance.
                            RevitMCPSDK.API.Interfaces.IRevitCommand command;

                            // 检查命令是否实现了可初始化接口
                            // Check whether the command implements the initializable interface.
                            if (typeof(IRevitCommandInitializable).IsAssignableFrom(type))
                            {
                                // 创建实例并初始化
                                // Create instance and initialize.
                                command = (IRevitCommand)Activator.CreateInstance(type);
                                ((IRevitCommandInitializable)command).Initialize(_uiApplication);
                            }
                            else
                            {
                                // 尝试查找接受 UIApplication 的构造函数
                                // Try searching for constructors that accept UIApplication.
                                var constructor = type.GetConstructor(new[] { typeof(UIApplication) });
                                if (constructor != null)
                                {
                                    command = (IRevitCommand)constructor.Invoke(new object[] { _uiApplication });
                                }
                                else
                                {
                                    // 使用无参构造函数
                                    // Use a parameterless constructor.
                                    command = (IRevitCommand)Activator.CreateInstance(type);
                                }
                            }

                            // 检查命令名称是否与配置匹配
                            // Check whether the command name matches the configuration.
                            if (command.CommandName == config.CommandName)
                            {
                                _commandRegistry.RegisterCommand(command);
                                _loadedCommands.Add(command.CommandName);
                                _logger.Info("已注册命令 [{0}] 来自 {1}\nRegistered command [{0}] from {1}",
                                    command.CommandName, Path.GetFileName(assemblyPath));
                                break; // 找到匹配的命令后退出循环 - Exit the loop after finding a matching command.
                            }
                        }
                        catch (Exception ex)
                        {
                            _failedCommands[config.CommandName] = ex.GetType().Name + ": " + ex.Message;
                            _logger.Error(
                                "创建命令实例失败 [{0}] (来自 {1}): {2}: {3}\n" +
                                "Failed to create command instance [{0}] (from {1}): {2}: {3}",
                                type.FullName,
                                Path.GetFileName(assemblyPath),
                                ex.GetType().FullName,
                                ex.Message);
                            for (var inner = ex.InnerException; inner != null; inner = inner.InnerException)
                            {
                                _logger.Error("  -> Inner: {0}: {1}", inner.GetType().FullName, inner.Message);
                            }
                            if (!string.IsNullOrEmpty(ex.StackTrace))
                            {
                                _logger.Error("  -> StackTrace: {0}", ex.StackTrace);
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _failedCommands[config.CommandName] = ex.GetType().Name + ": " + ex.Message;
                _logger.Error(
                    "加载命令程序集失败 ({0}): {1}: {2}\nFailed to load command assembly ({0}): {1}: {2}",
                    config.AssemblyPath, ex.GetType().FullName, ex.Message);
                for (var inner = ex.InnerException; inner != null; inner = inner.InnerException)
                {
                    _logger.Error("  -> Inner: {0}: {1}", inner.GetType().FullName, inner.Message);
                }
                if (ex is ReflectionTypeLoadException rtle && rtle.LoaderExceptions != null)
                {
                    foreach (var le in rtle.LoaderExceptions)
                    {
                        _logger.Error("  -> LoaderException: {0}: {1}", le?.GetType().FullName, le?.Message);
                    }
                }
            }
        }
    }
}
