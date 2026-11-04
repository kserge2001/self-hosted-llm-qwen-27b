"""Read-only Kubernetes functions the model may call.

Each function returns small plain data (dicts and lists), so the answer fits in the model's context.
Nothing here can change the cluster, and nothing reads Secrets or ConfigMaps.
"""

from kubernetes import client, config

MAX_ITEMS = 50  # keeps one tool result small; a busy namespace can have hundreds of pods


def load_kube_config() -> None:
    # Inside the cluster: the pod's service account. On a laptop: ~/.kube/config.
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def list_pods(namespace: str, core: client.CoreV1Api | None = None) -> list[dict]:
    core = core or client.CoreV1Api()
    pods = core.list_namespaced_pod(namespace, limit=MAX_ITEMS).items
    result = []
    for pod in pods:
        statuses = pod.status.container_statuses or []
        result.append(
            {
                "name": pod.metadata.name,
                "phase": pod.status.phase,
                "ready": f"{sum(1 for s in statuses if s.ready)}/{len(statuses)}",
                "restarts": sum(s.restart_count for s in statuses),
                "node": pod.spec.node_name,
                # The waiting reason (CrashLoopBackOff, ImagePullBackOff) is what people ask about.
                "waiting": [s.state.waiting.reason for s in statuses if s.state and s.state.waiting],
            }
        )
    return result


def describe_deployment(namespace: str, name: str, apps: client.AppsV1Api | None = None) -> dict:
    apps = apps or client.AppsV1Api()
    d = apps.read_namespaced_deployment(name, namespace)
    return {
        "name": d.metadata.name,
        "replicas": d.spec.replicas,
        "ready_replicas": d.status.ready_replicas or 0,
        "updated_replicas": d.status.updated_replicas or 0,
        "images": [c.image for c in d.spec.template.spec.containers],
        "conditions": [
            {"type": c.type, "status": c.status, "reason": c.reason, "message": c.message}
            for c in (d.status.conditions or [])
        ],
    }


def recent_events(namespace: str, limit: int = 20, core: client.CoreV1Api | None = None) -> list[dict]:
    core = core or client.CoreV1Api()
    events = core.list_namespaced_event(namespace).items

    def when(e):
        return e.last_timestamp or e.event_time or e.metadata.creation_timestamp

    events.sort(key=when, reverse=True)  # newest first
    limit = max(1, min(limit, MAX_ITEMS))
    return [
        {
            "time": str(when(e)),
            "type": e.type,
            "reason": e.reason,
            "object": f"{e.involved_object.kind}/{e.involved_object.name}",
            "message": e.message,
        }
        for e in events[:limit]
    ]


# Tool schemas in the OpenAI format. tests/tools.json is a copy for promptfoo; a unit test keeps them equal.
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_pods",
            "description": "List the pods in a namespace with phase, readiness, restarts and waiting reason.",
            "parameters": {
                "type": "object",
                "properties": {"namespace": {"type": "string", "description": "Kubernetes namespace"}},
                "required": ["namespace"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "describe_deployment",
            "description": "Show one deployment: replicas, ready replicas, images and conditions.",
            "parameters": {
                "type": "object",
                "properties": {
                    "namespace": {"type": "string", "description": "Kubernetes namespace"},
                    "name": {"type": "string", "description": "Deployment name"},
                },
                "required": ["namespace", "name"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "recent_events",
            "description": "Show the newest events in a namespace (warnings, scheduling, restarts).",
            "parameters": {
                "type": "object",
                "properties": {
                    "namespace": {"type": "string", "description": "Kubernetes namespace"},
                    "limit": {"type": "integer", "description": "How many events, 1 to 50", "default": 20},
                },
                "required": ["namespace"],
            },
        },
    },
]

FUNCTIONS = {"list_pods": list_pods, "describe_deployment": describe_deployment, "recent_events": recent_events}
