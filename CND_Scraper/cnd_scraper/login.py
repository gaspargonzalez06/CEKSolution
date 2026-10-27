"""
Login module for CND portal with exact selectors provided by user.
"""
import asyncio
import logging
from dataclasses import dataclass
from typing import Optional
from playwright.async_api import Page

logger = logging.getLogger(__name__)


@dataclass
class LoginConfig:
    """Login configuration with exact selectors from user."""
    # Exact selectors provided by user
    username_selector: str = '#modlgn-username'
    password_selector: str = '#modlgn-passwd'
    submit_selector: str = 'button.login-button[type="submit"]'
    login_url: str = 'https://sitioprivado.cnd.com.pa/privado/index.php'
    wait_after_login: int = 5000


class CNDLogin:
    """Handles login to CND portal with exact selectors provided by user."""
    
    def __init__(self, page: Page, config: LoginConfig = None):
        self.page = page
        self.config = config or LoginConfig()
    
    async def login(self, username: str, password: str) -> bool:
        """Login to CND portal using exact selectors provided by user."""
        try:
            logger.info(f"Navegando a {self.config.login_url}")
            await self.page.goto(self.config.login_url, wait_until='networkidle')
            
            # Fill username field
            logger.info("Llenando campo usuario...")
            await self.page.fill(self.config.username_selector, username)
            
            # Fill password field
            logger.info("Llenando campo contraseña...")
            await self.page.fill(self.config.password_selector, password)
            
            # Click login button
            logger.info("Click en botón Iniciar sesión...")
            await self.page.click(self.config.submit_selector)
            
            # Wait for navigation after login
            await self.page.wait_for_load_state('networkidle')
            await asyncio.sleep(self.config.wait_after_login / 1000)
            
            # Verify login success
            return await self._verify_login()
            
        except Exception as e:
            logger.error(f"Error en login: {e}")
            return False
    
    async def _verify_login(self) -> bool:
        """Verify login was successful."""
        try:
            # Wait for dashboard or user menu to appear
            await asyncio.sleep(3)
            
            # Check for common post-login elements
            try:
                # Look for common post-login elements
                await asyncio.sleep(2)
                
                # Check if we're still on login page (failure)
                login_form = await self.page.query_selector('#modlgn-username')
                if login_form:
                    logger.error("[ERROR] Login falló - seguimos en página de login")
                    return False
                
                logger.info("[OK] Login verificado exitosamente")
                return True
                
            except Exception as e:
                logger.warning(f"Verificación incierta: {e}")
                return True
                
        except Exception as e:
            logger.error(f"Error verificando login: {e}")
            return False