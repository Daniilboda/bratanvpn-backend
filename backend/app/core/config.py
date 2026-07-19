from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "BratanVPN API"
    app_version: str = "0.1.0"
    debug: bool = False
    database_url: str
    admin_api_key: str

    vpn_server_name: str = "Основной"
    vpn_server_host: str
    vpn_server_port: int
    vpn_server_public_key: str

    vpn_jc: int
    vpn_jmin: int
    vpn_jmax: int
    vpn_s1: int
    vpn_s2: int
    vpn_s3: int
    vpn_s4: int
    vpn_h1: int
    vpn_h2: int
    vpn_h3: int
    vpn_h4: int
    vpn_i1: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
