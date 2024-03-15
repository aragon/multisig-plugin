import {InstallationPrepared} from '../../generated/PluginSetupProcessor/PluginSetupProcessor';
import {MultisigPlugin} from '../../generated/schema';
import {Plugin as PluginTemplate} from '../../generated/templates';
import {PLUGIN_REPO_ADDRESS} from '../../imported/repo-address';
import {generatePluginEntityId} from '@aragon/osx-commons-subgraph';
import {Address, DataSourceContext, log} from '@graphprotocol/graph-ts';

export function handleInstallationPrepared(event: InstallationPrepared): void {
  const pluginRepo = event.params.pluginSetupRepo;

  // Determine if the prepared plugin matches the plugin repository address.
  const isTargetPlugin = pluginRepo == Address.fromString(PLUGIN_REPO_ADDRESS);

  // Ignore other plugins.
  if (!isTargetPlugin) {
    return;
  }

  const dao = event.params.dao;
  const pluginAddress = event.params.plugin;

  const pluginEntityId = generatePluginEntityId(pluginAddress);
  let pluginEntity = MultisigPlugin.load(pluginEntityId);

  if (!pluginEntity) {
    pluginEntity = new MultisigPlugin(pluginEntityId);
  }

  // Set the DAO and plugin address for the plugin entity.
  pluginEntity.dao = dao;
  pluginEntity.pluginAddress = pluginAddress;

  // Initialize a context for the plugin data source to enable indexing from the moment of preparation.
  const context = new DataSourceContext();
  // Include the DAO address in the context for future reference.
  context.setString('daoAddress', dao.toHexString());
  // Deploy a template for the plugin to facilitate individual contract indexing.
  PluginTemplate.createWithContext(pluginAddress, context);

  pluginEntity.save();
}
