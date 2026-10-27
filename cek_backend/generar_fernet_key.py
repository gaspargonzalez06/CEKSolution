# -*- coding: utf-8 -*-
"""Genera una FERNET_KEY para el .env."""
from cryptography.fernet import Fernet

if __name__ == "__main__":
    print(Fernet.generate_key().decode())
