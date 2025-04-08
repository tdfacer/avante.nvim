# Modified libs/utils.py for multiple host mounts
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import TYPE_CHECKING, List, Optional

if TYPE_CHECKING:
    from llama_index.core.schema import BaseNode

PATTERN_URI_PART = re.compile(r"(?P<uri>.+)__part_\d+")
METADATA_KEY_URI = "uri"


# Load host mount information from environment
def get_host_mounts() -> List[str]:
    """Get host mounts list from environment."""
    # Check if we have a JSON list of mounts from HOST_MOUNTS env var
    host_mounts_json = os.environ.get("HOST_MOUNTS")
    if host_mounts_json:
        try:
            return json.loads(host_mounts_json)
        except json.JSONDecodeError:
            pass

    # Fall back to the default behavior
    return ["/host"]


def uri_to_path(uri: str) -> Path:
    """Convert URI to path."""
    return Path(uri.replace("file://", ""))


def path_to_uri(file_path: Path) -> str:
    """Convert path to URI."""
    uri = file_path.as_uri()
    if file_path.is_dir():
        uri += "/"
    return uri


def is_local_uri(uri: str) -> bool:
    """Check if the URI is a path URI."""
    return uri.startswith("file://")


def is_remote_uri(uri: str) -> bool:
    """Check if the URI is an HTTPS URI or HTTP URI."""
    return uri.startswith(("https://", "http://"))


def is_path_node(node: BaseNode) -> bool:
    """Check if the node is a file node."""
    uri = get_node_uri(node)
    if not uri:
        return False
    return is_local_uri(uri)


def get_node_uri(node: BaseNode) -> str | None:
    """Get URI from node metadata."""
    uri = node.metadata.get(METADATA_KEY_URI)
    if not uri:
        doc_id = getattr(node, "doc_id", None)
        if doc_id:
            match = PATTERN_URI_PART.match(doc_id)
            uri = match.group("uri") if match else doc_id
    if uri:
        if uri.startswith("/"):
            uri = f"file://{uri}"
        return uri
    return None


def host_path_to_container_path(path: str) -> Optional[str]:
    """
    Convert a host path to a container path.

    Checks each mounted directory and converts paths that match
    one of the host mount points to the corresponding container path.
    """
    host_mounts = get_host_mounts()

    # Check if path matches any of our mount points
    for i, mount in enumerate(host_mounts, 1):
        mount_idx = i
        # If running in Docker, mount index starts from 1 (/host1, /host2...)
        # If running in Nix, the path might be direct
        container_mount = f"/host{mount_idx}"

        if path.startswith(mount):
            # Replace the host path with the container path
            rel_path = path[len(mount) :]
            if not rel_path.startswith("/"):
                rel_path = "/" + rel_path
            return f"{container_mount}{rel_path}"

    return None


def container_path_to_host_path(path: str) -> Optional[str]:
    """
    Convert a container path to a host path.

    Checks if the path starts with any of our container mounts
    and converts it to the corresponding host path.
    """
    host_mounts = get_host_mounts()

    # Check container mount pattern (e.g., /host1/path/to/file)
    for i, mount in enumerate(host_mounts, 1):
        mount_idx = i
        container_mount = f"/host{mount_idx}"

        if path.startswith(container_mount):
            # Replace the container path with the host path
            rel_path = path[len(container_mount) :]
            if not rel_path.startswith("/"):
                rel_path = "/" + rel_path
            return f"{mount}{rel_path}"

    return None


def inject_uri_to_node(node: BaseNode) -> None:
    """Inject file path into node metadata."""
    if METADATA_KEY_URI in node.metadata:
        return
    uri = get_node_uri(node)
    if uri:
        node.metadata[METADATA_KEY_URI] = uri
