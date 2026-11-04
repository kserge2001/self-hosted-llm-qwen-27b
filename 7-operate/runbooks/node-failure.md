# Runbook: a node fails

**Signs:** a node shows `NotReady`. Pods on it are stuck in `Terminating` or `Unknown`. An alert fires for fewer vLLM replicas.

1. Find the node and what ran on it:
   ```bash
   kubectl get nodes
   kubectl describe node <name>                       # Conditions and Events
   kubectl get pods -A -o wide --field-selector spec.nodeName=<name>
   ```
2. A GPU node: check the GPU. The NVIDIA DCGM panels in Grafana show XID errors or a GPU that went away.
3. Replace the node. For a Karpenter node, delete its NodeClaim. Karpenter drains it, terminates the machine and starts a new one:
   ```bash
   kubectl get nodeclaims -o wide                     # find the claim for this node
   kubectl delete nodeclaim <claim>
   ```
4. Watch the vLLM pod start on the new node: `kubectl -n serving get pods -w`. Loading the weights takes about 10 minutes. The other replica serves meanwhile, because the PodDisruptionBudget keeps one running.
5. If the same instance type fails again and again, write it down and tell AWS support.

**Why delete the NodeClaim and not the pod:** a broken machine stays broken. Karpenter gives you a fresh one.
