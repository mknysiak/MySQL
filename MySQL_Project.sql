select * from players where birthyear is not null order by birthyear asc ;
select * from salaries;
select * from school_details;
select * from schools order by yearid;

################################################################################################################################
-- a) in each deceade, how many schools were there that produced MLB players?
CREATE TEMPORARY TABLE grads as
with g as(
SELECT playerid, schoolid, yearid,
	ROW_NUMBER() over (partition by playerid, schoolid order by yearid desc) years
from schools
order by playerid asc
)
select * from g where years = 1;
select * from grads;

with number as(
select count(schoolid) no_of_schools, floor((yearid-1)/10)*10 decade
from grads
group by floor((yearid-1)/10)*10
order by floor((yearid-1)/10)*10
)
select no_of_schools, concat(decade+1,'-',decade+10) decade
from number;

-- b) what are the names of the top 5 schools that produced the most players?
select name_full school_name, count(playerid) no_of_players
from grads g
inner join school_details sd on g.schoolID = sd.schoolID
group by name_full
order by count(playerid) desc
limit 5;

-- c) for each decade, what were the names of the top 3 schools that produced the most players?
with top3 as(
with number as(
select schoolid, count(playerid) no_of_players , floor((yearid-1)/10)*10 decade
from grads g
group by schoolid, floor((yearid-1)/10)*10
order by floor((yearid-1)/10)*10, count(playerid) desc
)
select *,
	ROW_NUMBER() over (partition by decade order by no_of_players desc) ranking
from number
)
select name_full school_name, no_of_players, concat(decade+1,'-',decade+10) decade
from top3
inner join school_details sd on top3.schoolid = sd.schoolID
where ranking in (1,2,3)
order by decade asc, no_of_players desc;

################################################################################################################################
-- a) return the top 20% of teams in terms of average annual spending
with avg_annual_salaries as (
with  annual_salaries as (
select teamID, yearid, sum(salary) paid_salaries
from salaries
group by yearid, teamid
)
select teamid, round(avg(paid_salaries),0) avg_annual_salaries, ntile(5) over (order by avg(paid_salaries) desc) percentile
from annual_salaries
group by teamid
order by round(avg(paid_salaries),0) desc
)
select teamid, avg_annual_salaries
from avg_annual_salaries
where percentile = 1;

-- b) for each team show the cumulative sum of spending over the year
with aps as (
select teamID, yearid, sum(salary) paid_salaries
from salaries
group by yearid, teamid
)
select teamid, yearid, paid_salaries,
	sum(paid_salaries) over (partition by teamid order by yearid asc) cum_paid_salaries
from aps
order by teamid, yearid;

-- c) return the first year that each team's cumulative spending surpassed 1 billion
with first as (
with cps as (
with aps as (
select teamID, yearid, sum(salary) paid_salaries
from salaries
group by yearid, teamid
)
select teamid, yearid, paid_salaries,
	sum(paid_salaries) over (partition by teamid order by yearid asc) cum_paid_salaries,
	case when sum(paid_salaries) over (partition by teamid order by yearid asc) > 1000000000 then 1 else 0 end bilion
from aps
order by teamid, yearid
)
select *,
	sum(bilion) over (partition by teamid order by yearid asc) cum_bilion
from cps
)
select teamid, yearid, cum_paid_salaries
from first
where cum_bilion = 1;

################################################################################################################################
-- a) for each player calculate their age at their first (debut) game, their last game and their career length (in years). Sort from longest career to shortest one.
select namegiven, cast(concat(birthyear,'-',birthmonth,'-',birthday) as date) birth, debut, finalgame,
	TIMESTAMPDIFF(year, cast(concat(birthyear,'-',birthmonth,'-',birthday) as date), debut) debut_age,
	TIMESTAMPDIFF(year, cast(concat(birthyear,'-',birthmonth,'-',birthday) as date), finalgame) final_age,
    TIMESTAMPDIFF(year, debut, finalgame) carrer_length
from players
order by TIMESTAMPDIFF(year, debut, finalgame) desc;

-- b) what team did each player play on for their starting and ending years?
with first_last as(
with
first as(
select yearid, teamid, playerid,
	ROW_NUMBER() over (partition by playerid order by yearid asc) period
from salaries
order by playerID, yearid
),
last as (
select yearid, teamid, playerid,
	ROW_NUMBER() over (partition by playerid order by yearid desc) period
from salaries
order by playerID, yearid
)
select * from first where period = 1
union all
select * from last where period = 1
)
select yearid, teamid, playerid,
	case
    when ROW_NUMBER() over (partition by playerid order by yearid asc) = 1 then '1st Team'
    when ROW_NUMBER() over (partition by playerid order by yearid asc) = 2 then 'Last Team'
    end as teams
from first_last
order by playerid, yearid;

-- c)how many players started and ended on the same team and also played for over a decade?
with
first as(
select yearid, teamid, playerid,
	ROW_NUMBER() over (partition by playerid order by yearid asc) period
from salaries
order by playerID, yearid
),
last as (
select yearid, teamid, playerid,
	ROW_NUMBER() over (partition by playerid order by yearid desc) period
from salaries
order by playerID, yearid
),
first2 as (select * from first where period = 1),
last2 as (select * from last where period = 1),
first_last as(
select f.playerid, f.yearid first_year, f.teamid first_team, l.yearid last_year, l.teamid last_team
from first2 f
left join last2 l on f.playerid = l.playerid
)
select count(*)
from first_last
where 
	last_year - first_year > 10
    AND first_team = last_team;

################################################################################################################################
-- a)which players have the same birthday?
with bd as (
select namegiven, cast(concat(birthyear,'-',birthmonth,'-',birthday) as date) birth
from players
where cast(concat(birthyear,'-',birthmonth,'-',birthday) as date) is not null
order by cast(concat(birthyear,'-',birthmonth,'-',birthday) as date) asc
)
select bd1.namegiven, bd1.birth, bd2.namegiven, bd2.birth
from bd bd1
inner join bd bd2 on bd1.birth = bd2.birth
where bd1.namegiven < bd2.namegiven
order by bd1.namegiven;

-- b)create a summary table that shows for each team, what percent of players bat right, left and both.
with 
hand as(
select teamid, bats, count(bats) over (PARTITION BY teamid, bats) how_many
from salaries s
left join players p on s.playerid = p.playerid
where bats is not null
),
many as(
select teamid, bats, floor(avg(how_many)) how_many
from hand
group by teamid, bats
)
select *, round(how_many/sum(how_many) over (PARTITION BY teamid),2) percent
from many;

-- c)how have average height and weight as debut game changed over the years, and what's the decade-over-decade difference?
with
year_diff as(
select year(debut) debut, round(avg(weight)) avg_weight, round(avg(height)) avg_height
from players
where debut is not null
group by year(debut)
order by debut asc
),
decade as(
select debut, avg_weight, avg_height, concat(floor((debut-1)/10)*10+1,'-',floor((debut-1)/10)*10+10) decade
from year_diff
)
select *,
	round(avg(avg_weight) over (partition by decade)) decade_avg_weight,
	round(avg(avg_height) over (partition by decade)) decade_avg_height
from decade
order by debut asc;
