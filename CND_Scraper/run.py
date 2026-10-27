"""
Entry point for CND Scraper.
"""
import asyncio
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_formats import main

if __name__ == "__main__":
    asyncio.run(main())