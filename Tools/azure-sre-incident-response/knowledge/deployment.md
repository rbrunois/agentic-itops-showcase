# Deployment and rollback knowledge

The deployment blueprint is stored in `examples/deploy.yml` and is inactive.
If an operator deliberately activates it in their own repository, it builds
the sanitized app and deploys a revision after environment approval.
See [deployment setup](../docs/deployment.md).

Revision names can help locate a build, but inspect the actual image digest,
deployment record, and creation timestamp before claiming a commit caused an
incident. The crash-loop revision in this scenario is **manually injected**,
not a bad commit deployed by CI.

## Read-only inventory

Set `$scope` using the selected subscription, resource group, and app:

```powershell
az containerapp revision list --subscription $scope.SubscriptionId `
    --resource-group $scope.ResourceGroup --name $scope.AppName --all `
    --query "[].{name:name,active:properties.active,health:properties.healthState,state:properties.runningState,created:properties.createdTime,image:properties.template.containers[0].image}" `
    --output table
az containerapp show --subscription $scope.SubscriptionId `
    --resource-group $scope.ResourceGroup --name $scope.AppName `
    --query properties.configuration.ingress.traffic --output json
```

Latest log arrival is not a reliable active-revision selector. Query the
revision named in inventory and the incident state.

## Recovery proposal

Use the pre-injection record to identify original targets and weights.
Require verified healthy baseline revisions and explicit human approval
before changing traffic. The operator runs the
[guarded recovery procedure](../docs/demo-runbook.md), which checks the endpoint
and retires only the recorded injected revision.

Do not select a revision solely because it is running or lacks "broken" in its
name. Do not delete healthy revisions, overwrite incident state, or apply a
forward fix during the demonstration as a substitute for rollback.

After recovery, verify traffic, endpoint responses, replica health, and alert
state separately. Close incidents and publish summaries only with the
configured communication and approval authority.
