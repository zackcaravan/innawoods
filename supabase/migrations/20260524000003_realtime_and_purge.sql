-- innawoods — realtime broadcast + expiry purge.

-- ---------------------------------------------------------------------------
-- Realtime: clients subscribe per-party to these tables to get live updates.
-- REPLICA IDENTITY FULL so DELETE/UPDATE events carry enough to filter by party.
-- Guarded so re-running (or a table already in the publication) is a no-op.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'location_updates','pins','routes','messages','party_members'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Expiry purge. Ephemeral parties past expiry are deleted outright; persistent
-- parties keep their pins/routes but shed live location + chat data.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_expired_parties()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  DELETE FROM public.parties
  WHERE ephemeral AND expires_at IS NOT NULL AND expires_at < now();

  DELETE FROM public.location_updates lu USING public.parties p
  WHERE lu.party_id = p.id AND p.expires_at IS NOT NULL AND p.expires_at < now();

  DELETE FROM public.messages m USING public.parties p
  WHERE m.party_id = p.id AND p.expires_at IS NOT NULL AND p.expires_at < now();
END;
$$;

-- Schedule the purge every 5 minutes IF pg_cron is available on this project.
-- (Supabase: enable the pg_cron extension in the dashboard to activate this.)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    PERFORM cron.schedule(
      'innawoods-purge-expired',
      '*/5 * * * *',
      $cron$ SELECT public.purge_expired_parties(); $cron$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not permitted here; purge can be invoked manually or via Edge cron.
  RAISE NOTICE 'pg_cron not scheduled: %', SQLERRM;
END $$;
