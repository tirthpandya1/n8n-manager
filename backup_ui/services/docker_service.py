"""
Docker Service
Handles Docker container operations for N8N instances
"""
import subprocess
import json
from typing import List, Dict, Optional


class DockerService:
    """Service for Docker container operations"""

    @staticmethod
    def list_n8n_containers() -> List[Dict[str, str]]:
        """List all N8N Docker containers"""
        try:
            # Get all containers with n8n in the name
            cmd = ["docker", "ps", "-a", "--format", "json", "--filter", "name=n8n"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            containers = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    try:
                        container = json.loads(line)
                        containers.append({
                            'id': container.get('ID', ''),
                            'name': container.get('Names', ''),
                            'status': container.get('State', ''),
                            'image': container.get('Image', ''),
                            'created': container.get('CreatedAt', '')
                        })
                    except json.JSONDecodeError:
                        continue

            return containers
        except subprocess.CalledProcessError:
            return []
        except FileNotFoundError:
            # Docker not installed
            return []

    @staticmethod
    def get_container_status(container_name: str) -> Optional[Dict[str, str]]:
        """Get status of a specific container"""
        try:
            cmd = ["docker", "inspect", container_name, "--format", "json"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            data = json.loads(result.stdout)
            if data:
                container = data[0]
                state = container.get('State', {})
                return {
                    'name': container.get('Name', '').lstrip('/'),
                    'id': container.get('Id', '')[:12],
                    'status': state.get('Status', 'unknown'),
                    'running': state.get('Running', False),
                    'created': container.get('Created', ''),
                    'image': container.get('Config', {}).get('Image', '')
                }
        except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
            pass

        return None

    @staticmethod
    def is_docker_available() -> bool:
        """Check if Docker is available"""
        try:
            subprocess.run(["docker", "--version"],
                         capture_output=True,
                         check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    @staticmethod
    def start_container(container_name: str) -> bool:
        """Start a stopped container"""
        try:
            subprocess.run(["docker", "start", container_name],
                         capture_output=True,
                         check=True)
            return True
        except subprocess.CalledProcessError:
            return False

    @staticmethod
    def stop_container(container_name: str) -> bool:
        """Stop a running container"""
        try:
            subprocess.run(["docker", "stop", container_name],
                         capture_output=True,
                         check=True)
            return True
        except subprocess.CalledProcessError:
            return False

    @staticmethod
    def restart_container(container_name: str) -> bool:
        """Restart a container"""
        try:
            subprocess.run(["docker", "restart", container_name],
                         capture_output=True,
                         check=True)
            return True
        except subprocess.CalledProcessError:
            return False
