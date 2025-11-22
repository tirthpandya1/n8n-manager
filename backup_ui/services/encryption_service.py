"""
Encryption Service
Handles N8N encryption key management
"""
import os
import json
import subprocess
from pathlib import Path
from typing import Optional, Dict


class EncryptionService:
    """Service for encryption key management"""

    @staticmethod
    def get_encryption_key() -> Optional[Dict[str, str]]:
        """
        Get the N8N encryption key from various sources
        Returns dict with key info and source
        """
        # Try environment variable first
        env_key = os.environ.get('N8N_ENCRYPTION_KEY')
        if env_key:
            return {
                'key': env_key,
                'source': 'environment',
                'masked': EncryptionService._mask_key(env_key),
                'length': len(env_key),
                'valid': len(env_key) == 32
            }

        # Try config file
        config_path = Path.home() / '.n8n' / 'config'
        if config_path.exists():
            try:
                with open(config_path, 'r') as f:
                    config = json.load(f)
                    key = config.get('encryptionKey')
                    if key:
                        return {
                            'key': key,
                            'source': 'config_file',
                            'path': str(config_path),
                            'masked': EncryptionService._mask_key(key),
                            'length': len(key),
                            'valid': len(key) == 32
                        }
            except (json.JSONDecodeError, IOError):
                pass

        # Try custom config location
        custom_config = Path(__file__).parent.parent.parent / 'config' / '.n8n_encryption_key'
        if custom_config.exists():
            try:
                with open(custom_config, 'r') as f:
                    key = f.read().strip()
                    if key:
                        return {
                            'key': key,
                            'source': 'custom_config',
                            'path': str(custom_config),
                            'masked': EncryptionService._mask_key(key),
                            'length': len(key),
                            'valid': len(key) == 32
                        }
            except IOError:
                pass

        return None

    @staticmethod
    def _mask_key(key: str) -> str:
        """Mask encryption key for display"""
        if len(key) <= 16:
            return '*' * len(key)
        return f"{key[:8]}...{key[-8:]}"

    @staticmethod
    def generate_new_key() -> str:
        """Generate a new 32-character encryption key"""
        try:
            # Try openssl first
            result = subprocess.run(
                ["openssl", "rand", "-hex", "16"],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Fall back to Python's secrets module
            import secrets
            return secrets.token_hex(16)

    @staticmethod
    def save_encryption_key(key: str, location: str = 'custom') -> Dict[str, any]:
        """
        Save encryption key to specified location
        Returns status and path
        """
        if len(key) != 32:
            return {
                'success': False,
                'error': f'Invalid key length: {len(key)}. Must be 32 characters.'
            }

        if location == 'custom':
            # Save to custom config location
            config_dir = Path(__file__).parent.parent.parent / 'config'
            config_dir.mkdir(exist_ok=True)
            key_file = config_dir / '.n8n_encryption_key'

            try:
                with open(key_file, 'w') as f:
                    f.write(key)
                os.chmod(key_file, 0o600)  # Set restrictive permissions
                return {
                    'success': True,
                    'path': str(key_file),
                    'message': 'Key saved successfully'
                }
            except IOError as e:
                return {
                    'success': False,
                    'error': f'Failed to save key: {str(e)}'
                }

        elif location == 'n8n_config':
            # Save to ~/.n8n/config
            config_path = Path.home() / '.n8n' / 'config'
            config_path.parent.mkdir(exist_ok=True)

            try:
                # Read existing config or create new
                config = {}
                if config_path.exists():
                    with open(config_path, 'r') as f:
                        config = json.load(f)

                config['encryptionKey'] = key

                with open(config_path, 'w') as f:
                    json.dump(config, f, indent=2)

                return {
                    'success': True,
                    'path': str(config_path),
                    'message': 'Key saved to N8N config'
                }
            except (IOError, json.JSONDecodeError) as e:
                return {
                    'success': False,
                    'error': f'Failed to save key: {str(e)}'
                }

        return {
            'success': False,
            'error': 'Invalid location specified'
        }

    @staticmethod
    def validate_key(key: str) -> Dict[str, any]:
        """Validate encryption key format"""
        return {
            'valid': len(key) == 32,
            'length': len(key),
            'expected_length': 32,
            'is_hex': all(c in '0123456789abcdefABCDEF' for c in key)
        }
