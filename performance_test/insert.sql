insert into game_exp
select
  NULL,
  host_year,
  host_nation,
  host_city,
  stadium_name,
  stadium_area,
  stadium_seats,
  stadium_address,
  athlete_name,
  athlete_gender,
  athlete_event,
  nation_name,
  nation_continent,
  nation_capital,
  opening_date,
  closing_date,
  game_date,
  mascot,
  slogan,
  introduction
from
  game_exp;

