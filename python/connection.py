import pyodbc
from sqlalchemy import create_engine
from urllib.parse import quote


server = "sql-nova-analyticsserver.database.windows.net"
database = "free-sql-db-9377179"
username = "admin_nova_juancho"
password = "***REMOVED***"  


# Conexión pyodbc
def get_connection():
    connection_string = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )
    return pyodbc.connect(connection_string)


# Conexión SQLAlchemy (forma correcta para Azure SQL)
engine = create_engine(
    f"mssql+pyodbc://{quote(username)}:{quote(password)}@{server}/{database}?"
    f"driver=ODBC+Driver+18+for+SQL+Server&"
    f"Encrypt=yes&"
    f"TrustServerCertificate=no&"
    f"Connection+Timeout=30",
    poolclass=None  # Evita problemas con pool de conexiones
)