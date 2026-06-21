defmodule DebtStalker.Repo.Migrations.AddOutboxTriggers do
  use Ecto.Migration

  def up do
    # Trigger function: on INSERT into credit_applications → create application.created event
    execute("""
    CREATE OR REPLACE FUNCTION fn_application_created_event()
    RETURNS TRIGGER AS $$
    BEGIN
      INSERT INTO application_events (id, application_id, event_type, payload, inserted_at)
      VALUES (
        gen_random_uuid(),
        NEW.id,
        'application.created',
        jsonb_build_object('country', NEW.country, 'status', NEW.status),
        NOW()
      );
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_application_created
    AFTER INSERT ON credit_applications
    FOR EACH ROW
    EXECUTE FUNCTION fn_application_created_event();
    """)

    # Trigger function: on UPDATE of status → create application.status_changed event
    execute("""
    CREATE OR REPLACE FUNCTION fn_application_status_changed_event()
    RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO application_events (id, application_id, event_type, payload, inserted_at)
        VALUES (
          gen_random_uuid(),
          NEW.id,
          'application.status_changed',
          jsonb_build_object(
            'from_status', OLD.status,
            'to_status', NEW.status,
            'country', NEW.country
          ),
          NOW()
        );
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER trg_application_status_changed
    AFTER UPDATE OF status ON credit_applications
    FOR EACH ROW
    EXECUTE FUNCTION fn_application_status_changed_event();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS trg_application_status_changed ON credit_applications;")
    execute("DROP FUNCTION IF EXISTS fn_application_status_changed_event();")
    execute("DROP TRIGGER IF EXISTS trg_application_created ON credit_applications;")
    execute("DROP FUNCTION IF EXISTS fn_application_created_event();")
  end
end
