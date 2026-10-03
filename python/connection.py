"""
Conexión centralizada a Azure SQL.

Las credenciales se leen de variables de entorno (archivo .env en la raíz
del proyecto). Nunca escribas credenciales directamente en este archivo.

Prueba rápida de conexión:
    python python/connection.py
"""

import os
from pathlib import Path

import pyodbc
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

# Carga el .env de la raíz del proyecto, sin importar desde qué carpeta se ejecute
PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_ROOT / ".env")

REQUIRED_VARS = [
    "AZURE_SQL_SERVER",
    "AZURE_SQL_DATABASE",
    "AZURE_SQL_USER",
    "AZURE_SQL_PASSWORD",
]

missing = [var for var in REQUIRED_VARS if not os.getenv(var)]
if missing:
    raise RuntimeError(
        f"Faltan variables de entorno: {', '.join(missing)}. "
        "Copia .env.example como .env y completa los valores."
    )

SERVER = os.environ["AZURE_SQL_SERVER"]
DATABASE = os.environ["AZURE_SQL_DATABASE"]
DB_USER = os.environ["AZURE_SQL_USER"]
DB_SECRET = os.environ["AZURE_SQL_PASSWORD"]
ODBC_DRIVER = os.getenv("AZURE_SQL_DRIVER", "ODBC Driver 18 for SQL Server")


# Conexión pyodbc (útil para consultas puntuales)
def get_connection():
    connection_string = (
        f"DRIVER={{{ODBC_DRIVER}}};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        f"UID={DB_USER};"
        f"PWD={DB_SECRET};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )
    return pyodbc.connect(connection_string)


# Engine SQLAlchemy (lo usan los scripts del simulador)
# URL.create escapa caracteres especiales de la contraseña automáticamente
connection_url = URL.create(
    "mssql+pyodbc",
    username=DB_USER,
    password=DB_SECRET,
    host=SERVER,
    database=DATABASE,
    query={
        "driver": ODBC_DRIVER,
        "Encrypt": "yes",
        "TrustServerCertificate": "no",
        "Connection Timeout": "30",
    },
)

# fast_executemany: inserciones masivas mucho más rápidas con pyodbc
engine = create_engine(connection_url, pool_pre_ping=True, fast_executemany=True)


if __name__ == "__main__":
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT DB_NAME() AS db, SUSER_NAME() AS login_name")
        ).one()
        print(f"Conexión OK -> base: {row.db} | login: {row.login_name}")
