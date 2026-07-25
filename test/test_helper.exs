ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Gesttalt.Repo, :manual)

# Modules whose calls Open Graph tests replace with Mimic stubs so they never
# launch a real browser or touch object storage.
Mimic.copy(Carta)
Mimic.copy(Gesttalt.MediaStorage)
