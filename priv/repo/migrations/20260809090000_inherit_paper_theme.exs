defmodule Gesttalt.Repo.Migrations.InheritPaperTheme do
  use Ecto.Migration

  @default_variables_base64 "eyJjb2xvcnMiOnsiYWNjZW50IjoiI2I0NTMwOSIsImJhY2tncm91bmQiOiIjZmRmYmY3IiwiYm9yZGVyIjoiI2U0ZGRkMiIsImhpZ2hsaWdodCI6IiNmZmYxYTgiLCJtdXRlZCI6IiNmN2Y0ZWYiLCJtdXRlZFRleHQiOiIjNWM1NzUxIiwicHJpbWFyeSI6IiMwMDYyY2MiLCJzZWNvbmRhcnkiOiIjNWI0YjhhIiwic3VyZmFjZSI6IiNmN2Y0ZWYiLCJ0ZXh0IjoiIzE3MTQxMSJ9LCJmb250U2l6ZXMiOnsiYm9keSI6IjFyZW0iLCJoZWFkaW5nIjoiY2xhbXAoMS43NXJlbSwgNXZ3LCAyLjZyZW0pIiwibGVhZCI6IjEuMXJlbSIsInNtYWxsIjoiMC44NzVyZW0ifSwiZm9udFdlaWdodHMiOnsiYm9keSI6IjQwMCIsImJvbGQiOiI3MDAiLCJoZWFkaW5nIjoiNzAwIn0sImZvbnRzIjp7ImJvZHkiOiJzeXN0ZW0tdWksIC1hcHBsZS1zeXN0ZW0sIFwiU2Vnb2UgVUlcIiwgc2Fucy1zZXJpZiIsImhlYWRpbmciOiJzeXN0ZW0tdWksIC1hcHBsZS1zeXN0ZW0sIFwiU2Vnb2UgVUlcIiwgc2Fucy1zZXJpZiIsIm1vbm9zcGFjZSI6InVpLW1vbm9zcGFjZSwgbW9ub3NwYWNlIn0sImxpbmVIZWlnaHRzIjp7ImJvZHkiOiIxLjciLCJoZWFkaW5nIjoiMS4xNSJ9LCJyYWRpaSI6eyJsYXJnZSI6IjFyZW0iLCJtZWRpdW0iOiIwLjVyZW0iLCJyb3VuZCI6Ijk5OTlweCIsInNtYWxsIjoiMC4ycmVtIn0sInNoYWRvd3MiOnsiY2FyZCI6IjAgMXB4IDNweCByZ2IoMjMgMjAgMTcgLyAwLjEyKSJ9LCJzaXplcyI6eyJjb250ZW50IjoiNzYwcHgifSwic3BhY2UiOnsiMSI6IjAuMjVyZW0iLCIyIjoiMC41cmVtIiwiMyI6IjFyZW0iLCI0IjoiMS41cmVtIiwiNSI6IjIuNXJlbSIsIjYiOiI0cmVtIn19"

  def up do
    alter table(:themes) do
      add :inherited, :boolean, null: false, default: false
    end

    execute("""
    UPDATE themes
    SET inherited = true
    WHERE name = 'Paper'
      AND photography_template IS NULL
      AND md5(stylesheet) = 'c290a86db001f576434d1b90304c2775'
      AND md5(index_template) = '8583c1cc6aeeb49242dad315fcd8be09'
      AND md5(article_template) = '00592d5ae09dc0d08e27adad7e9c288b'
      AND md5(page_template) = '45d591121c7e0480ce2fcae121db09cd'
      AND variables = convert_from(decode('#{@default_variables_base64}', 'base64'), 'utf8')::jsonb
    """)
  end

  def down do
    alter table(:themes) do
      remove :inherited
    end
  end
end
