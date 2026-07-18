REVOKE CREATE ON SCHEMA public FROM PUBLIC;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mhglauncher_admin') THEN
    CREATE ROLE mhglauncher_admin LOGIN PASSWORD 'mhglauncher_admin';
  END IF;
END $$;
GRANT CONNECT, CREATE ON DATABASE mhglauncher TO mhglauncher_admin;
