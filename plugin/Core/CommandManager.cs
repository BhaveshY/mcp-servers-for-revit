using Autodesk.Revit.UI;
using RevitMCPSDK.API.Interfaces;
using RevitMCPSDK.API.Utils;
using revit_mcp_plugin.Configuration;
using revit_mcp_plugin.Utils;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
            _logger.Info("开始加载命令\nStart loading command.");
            string currentVersion = _versionAdapter.GetRevitVersion();
            _logger.Info("当前 Revit 版本: {0}\nCurrent Revit version: {0}", currentVersion);
            _commandRegistry.ClearCommands();

            if (_configManager.Config?.Commands == null || !_configManager.Config.Commands.Any())
            {
                _logger.Warning("没有配置任何命令\nNo commands are configured.");
                return;
            }

            var loadRequests = new List<CommandLoadRequest>();

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
                        _logger.Warning("命令 {0} 不支持当前 Revit 版本 {1}，已跳过\nThe command {0} is not supported by the current Revit version ({1}) and it has been skipped.",
                            commandConfig.CommandName, currentVersion);
                        continue;
                    }

                    string assemblyPath = ResolveAssemblyPath(commandConfig.AssemblyPath, currentVersion);
                    if (!File.Exists(assemblyPath))
                    {
                        _logger.Error("命令程序集不存在: {0}\nCommand assembly does not exist: {0}", assemblyPath);
                        continue;
                    }

                    loadRequests.Add(new CommandLoadRequest(commandConfig, assemblyPath));
                }
                catch (Exception ex)
                {
                    _logger.Error("加载命令 {0} 失败: {1}\nFailed to load command {0}: {1}", commandConfig.CommandName, ex.Message);
                }
            }

            foreach (var group in loadRequests.GroupBy(request => request.AssemblyPath, StringComparer.OrdinalIgnoreCase))
            {
                LoadCommandsFromAssembly(group.Key, group.Select(request => request.Config).ToList());
            }

            _logger.Info("命令加载完成\nCommand loading complete.");
        }

        /// <summary>
        /// 加载特定程序集中的特定命令
        /// Loads specific commands in specific assemblies.
        /// </summary>
        /// <param name="config">Configuration class describing the command.</param>
        private string ResolveAssemblyPath(string configuredAssemblyPath, string currentVersion)
        {
            string assemblyPath = configuredAssemblyPath.Contains("{VERSION}")
                ? configuredAssemblyPath.Replace("{VERSION}", currentVersion)
                : configuredAssemblyPath;

            if (!Path.IsPathRooted(assemblyPath))
            {
                string baseDir = PathManager.GetCommandsDirectoryPath();
                assemblyPath = Path.Combine(baseDir, assemblyPath);
            }

            return Path.GetFullPath(assemblyPath);
        }

        private void LoadCommandsFromAssembly(string assemblyPath, IList<CommandConfig> configs)
        {
            try
            {
                // 加载程序集
                // Load assembly.
                Assembly assembly = Assembly.LoadFrom(assemblyPath);
                var pendingCommandNames = new HashSet<string>(
                    configs.Select(config => config.CommandName),
                    StringComparer.OrdinalIgnoreCase);

                // 查找实现 IRevitCommand 接口的类型
                // Find types that implement the IRevitCommand interface.
                foreach (Type type in assembly.GetTypes())
                {
                    if (!pendingCommandNames.Any())
                    {
                        break;
                    }

                    if (typeof(RevitMCPSDK.API.Interfaces.IRevitCommand).IsAssignableFrom(type) &&
                        !type.IsInterface &&
                        !type.IsAbstract)
                    {
                        try
                        {
                            IRevitCommand command = CreateCommandInstance(type);

                            // 检查命令名称是否与配置匹配
                            // Check whether the command name matches the configuration.
                            if (pendingCommandNames.Contains(command.CommandName))
                            {
                                _commandRegistry.RegisterCommand(command);
                                pendingCommandNames.Remove(command.CommandName);
                                _logger.Info("命令注册成功 [{0}]: {1}\nRegistered command [{0}]: {1}",
                                    command.CommandName, Path.GetFileName(assemblyPath));
                            }
                        }
                        catch (Exception ex)
                        {
                            _logger.Error("创建命令实例失败 [{0}]: {1}\nFailed to create command instance [{0}]: {1}", type.FullName, ex.Message);
                        }
                    }
                }

                foreach (var missingCommandName in pendingCommandNames)
                {
                    _logger.Warning("程序集 {0} 中未找到配置的命令: {1}\nConfigured command not found in assembly {0}: {1}",
                        Path.GetFileName(assemblyPath), missingCommandName);
                }
            }
            catch (Exception ex)
            {
                _logger.Error("加载命令程序集失败: {0}\nFailed to load command assembly: {0}", ex.Message);
            }
        }

        private IRevitCommand CreateCommandInstance(Type type)
        {
            if (typeof(IRevitCommandInitializable).IsAssignableFrom(type))
            {
                var command = (IRevitCommand)Activator.CreateInstance(type);
                ((IRevitCommandInitializable)command).Initialize(_uiApplication);
                return command;
            }

            var constructor = type.GetConstructor(new[] { typeof(UIApplication) });
            if (constructor != null)
            {
                return (IRevitCommand)constructor.Invoke(new object[] { _uiApplication });
            }

            return (IRevitCommand)Activator.CreateInstance(type);
        }

        private class CommandLoadRequest
        {
            public CommandLoadRequest(CommandConfig config, string assemblyPath)
            {
                Config = config;
                AssemblyPath = assemblyPath;
            }

            public CommandConfig Config { get; }
            public string AssemblyPath { get; }
        }
    }
}
