# Seeds for the companion UI — creates 100 randomized demo applications and
# prints demo credentials.
#
#     mix run priv/repo/seeds.exs

alias DebtStalker.Applications.CreditApplication
alias DebtStalker.Repo
alias DebtStalkerWeb.Auth.Token

IO.puts("\n=== Seeding Demo Data ===\n")

first_names = [
  "Juan",
  "Maria",
  "Carlos",
  "Ana",
  "Pedro",
  "Sofia",
  "Luis",
  "Lucia",
  "Roberto",
  "Fernando",
  "Diego",
  "Elena",
  "Miguel",
  "Isabel",
  "Jose",
  "Carmen",
  "Antonio",
  "Laura",
  "Francisco",
  "Pilar"
]

last_names = [
  "Garcia",
  "Rodriguez",
  "Martinez",
  "Lopez",
  "Sanchez",
  "Perez",
  "Gomez",
  "Fernandez",
  "Torres",
  "Diaz",
  "Hernandez",
  "Ramirez",
  "Moreno",
  "Alvarez",
  "Jimenez",
  "Ruiz",
  "Vazquez",
  "Molina",
  "Castro",
  "Ortega"
]

statuses = CreditApplication.valid_statuses()

now = DateTime.utc_now() |> DateTime.to_unix()
ninety_days_in_seconds = 90 * 24 * 60 * 60

dni_letters = "TRWAGMYFPDXBNJZSQVHLCKE"

random_dni = fn ->
  digits = :rand.uniform(99_999_999)
  digits_str = String.pad_leading(Integer.to_string(digits), 8, "0")
  letter = String.at(dni_letters, rem(digits, 23))
  digits_str <> letter
end

random_curp = fn ->
  letters = for(_ <- 1..4, do: <<Enum.random(?A..?Z)>>) |> Enum.join()
  year = String.pad_leading(Integer.to_string(Enum.random(50..99)), 2, "0")
  month = String.pad_leading(Integer.to_string(Enum.random(1..12)), 2, "0")
  day = String.pad_leading(Integer.to_string(Enum.random(1..28)), 2, "0")

  tail =
    for(_ <- 1..8, do: <<Enum.random([Enum.random(?A..?Z), Enum.random(?0..?9)])>>)
    |> Enum.join()

  letters <> year <> month <> day <> tail
end

random_name = fn ->
  "#{Enum.random(first_names)} #{Enum.random(last_names)} #{Enum.random(last_names)}"
end

random_decimal = fn min, max ->
  Decimal.new(Integer.to_string(Enum.random(min..max)))
end

random_date = fn ->
  seconds_ago = Enum.random(0..ninety_days_in_seconds)
  DateTime.from_unix!(now - seconds_ago, :second)
end

random_country = fn ->
  Enum.random(["ES", "MX"])
end

created_count =
  Enum.reduce(1..100, 0, fn _, acc ->
    country = random_country.()

    document =
      if country == "ES" do
        random_dni.()
      else
        random_curp.()
      end

    requested_amount = random_decimal.(1_000, 100_000)
    monthly_income = random_decimal.(1_000, 20_000)
    status = Enum.random(statuses)

    additional_review_required =
      status == "additional_review" || Enum.random([true, false, false])

    attrs = %{
      country: country,
      full_name: random_name.(),
      identity_document: document,
      requested_amount: requested_amount,
      monthly_income: monthly_income,
      status: status,
      additional_review_required: additional_review_required,
      application_date: random_date.(),
      provider_summary: %{}
    }

    case %CreditApplication{}
         |> CreditApplication.changeset(attrs)
         |> Repo.insert() do
      {:ok, app} ->
        IO.puts(
          "  Created: #{app.country} | #{app.full_name} | #{app.status} | amount=#{app.requested_amount}"
        )

        acc + 1

      {:error, changeset} ->
        IO.puts("  FAILED: #{document} — #{inspect(changeset.errors)}")
        acc
    end
  end)

IO.puts("\nCreated #{created_count} demo applications")

IO.puts("\n=== Demo Credentials ===\n")

{:ok, read_token} = Token.generate_token("read")
{:ok, update_token} = Token.generate_token("update")

IO.puts("  Admin UI password: #{Application.fetch_env!(:debt_stalker, :admin_password)}")
IO.puts("  READ API token:    #{read_token}")
IO.puts("  UPDATE API token:  #{update_token}")
IO.puts("")
IO.puts("  Usage:")
IO.puts("    curl -H 'Authorization: Bearer <token>' http://localhost:4000/api/applications")
IO.puts("")
IO.puts("=== Seeding Complete ===\n")
