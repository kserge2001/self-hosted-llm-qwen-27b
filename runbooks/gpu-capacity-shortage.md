# Runbook: no GPU capacity

**Signs:** a vLLM pod stays `Pending`. Karpenter cannot start a GPU node.

1. Find the reason:
   ```bash
   kubectl -n serving get pods
   kubectl get nodeclaims
   kubectl describe nodeclaim <name>          # look for InsufficientInstanceCapacity
   kubectl -n kube-system logs deploy/karpenter | grep -i -m 20 insufficient
   ```
2. The GPU NodePool already allows `g6e.xlarge`, `g6e.2xlarge` and `g6e.4xlarge` in every zone of the VPC. So if AWS has none of them, choose one of these:
   - **Wait.** Karpenter keeps trying by itself, with a short pause between tries. Capacity often comes back within hours.
   - **Reserve capacity.** Create an On-Demand Capacity Reservation for g6e in the EC2 console (Capacity Reservations). You pay for it from the start, used or not. Karpenter uses it after you add it to `capacityReservationSelectorTerms` in the `gpu` EC2NodeClass and add `reserved` to `karpenter.sh/capacity-type` in the `gpu` NodePool (`platform/karpenter`, in Git). EC2 Capacity Blocks do not list g6e (checked 2026-10-28: only P and Trn types).
   - **Raise the quota** if the error says `VcpuLimitExceeded`: Service Quotas, "Running On-Demand G and VT instances". A g6e.4xlarge needs 16 vCPUs.
   - **Allow another GPU family** in the `gpu` NodePool, in Git. First check that the model fits in one GPU: the FP8 weights are close to 30 GB, plus the KV cache for 32768 tokens. A 24 GB GPU (g5, g6) is too small. A bigger GPU costs more per hour, so move back when g6e capacity returns.
3. While you wait, the gateway still serves from the replicas that run. Tell the teams that answers may be slower.

**Why it happens:** us-east-1 often runs out of L40S GPUs. A company reserves capacity with On-Demand Capacity Reservations (the guide's production doc).
