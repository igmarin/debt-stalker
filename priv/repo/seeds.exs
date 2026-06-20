# Seeds for Phase 1 — creates 10 demo applications and prints JWT tokens
#
#     mix run priv/repo/seeds.exs

alias DebtStalker.Applications
alias DebtStalkerWeb.Auth.Token

IO.puts("\n=== Seeding Phase 1 Demo Data ===\n")

# Seed applications: 5 ES + 5 MX
es_applications = [
  %{
    country: "ES",
    full_name: "Juan Garcia Lopez",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  },
  %{
    country: "ES",
    full_name: "Maria Rodriguez Fernandez",
    identity_document: "87654321X",
    requested_amount: Decimal.new("18000"),
    monthly_income: Decimal.new("1200")
  },
  %{
    country: "ES",
    full_name: "Carlos Martinez Ruiz",
    identity_document: "11111111H",
    requested_amount: Decimal.new("3000"),
    monthly_income: Decimal.new("3500")
  },
  %{
    country: "ES",
    full_name: "Ana Sanchez Torres",
    identity_document: "22222222J",
    requested_amount: Decimal.new("25000"),
    monthly_income: Decimal.new("1800")
  },
  %{
    country: "ES",
    full_name: "Pedro Diaz Moreno",
    identity_document: "33333333P",
    requested_amount: Decimal.new("7500"),
    monthly_income: Decimal.new("2500")
  }
]

mx_applications = [
  %{
    country: "MX",
    full_name: "Roberto Hernandez Gutierrez",
    identity_document: "GARC850101HDFRRL09",
    requested_amount: Decimal.new("80000"),
    monthly_income: Decimal.new("15000")
  },
  %{
    country: "MX",
    full_name: "Lucia Perez Ramirez",
    identity_document: "PERL900215MDFRRC05",
    requested_amount: Decimal.new("200000"),
    monthly_income: Decimal.new("12000")
  },
  %{
    country: "MX",
    full_name: "Fernando Lopez Martinez",
    identity_document: "LOMF880330HDFPRT01",
    requested_amount: Decimal.new("50000"),
    monthly_income: Decimal.new("20000")
  },
  %{
    country: "MX",
    full_name: "Sofia Ramirez Diaz",
    identity_document: "RADS950512MDFRMS08",
    requested_amount: Decimal.new("150000"),
    monthly_income: Decimal.new("18000")
  },
  %{
    country: "MX",
    full_name: "Diego Torres Morales",
    identity_document: "TOMD700820HDFMRG02",
    requested_amount: Decimal.new("30000"),
    monthly_income: Decimal.new("25000")
  }
]

all_applications = es_applications ++ mx_applications

Enum.each(all_applications, fn attrs ->
  case Applications.create_application(attrs) do
    {:ok, app} ->
      IO.puts("  Created: #{app.country} | #{app.full_name} | #{app.status} | amount=#{app.requested_amount}")

    {:error, reason} ->
      IO.puts("  FAILED: #{attrs.full_name} — #{inspect(reason)}")
  end
end)

IO.puts("\n=== Demo JWT Tokens (valid 1 hour) ===\n")

{:ok, read_token} = Token.generate_token("read")
{:ok, update_token} = Token.generate_token("update")

IO.puts("  READ token:   #{read_token}")
IO.puts("  UPDATE token: #{update_token}")
IO.puts("")
IO.puts("  Usage:")
IO.puts("    curl -H 'Authorization: Bearer <token>' http://localhost:4000/api/applications")
IO.puts("")
IO.puts("=== Seeding Complete (10 applications) ===\n")
