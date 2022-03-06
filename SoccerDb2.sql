-- This is a continuation to the Exercises from the SoccerDB1.
--We are using the same database to run the following queries.

--Get a list with each code for the phases of the tournament with code and name for the phase, 
--mathes played for each, avg of goals for all the matches of the phase and number of different stadiums.


SELECT
	p.phase_code, 
	p.phase_name, 
	COUNT (m.*) AS num_games, 
	ROUND(AVG (m.home_goals+m.visitor_goals),2) AS avg_goals, 
	COUNT (DISTINCT m.stadium_code) AS num_stadiums
	
FROM euro2021.tb_phase p

INNER JOIN euro2021.tb_match m
	  ON p.phase_code = m.phase_code
	  

GROUP BY p.phase_code
ORDER BY avg_goals desc
;


-- List all matches showing:
-- Name of the local team, name of the visitor team, date, referee name, name of the phase for the match.
-- For the result we are going to show 1 if the local team won, X if there was a draw and 2 if the visitor won.


SELECT 
	c1.country_name AS home,
	c2.country_name AS visitor,
	m.match_date,
	r.referee_name,
	p.phase_name,
	CASE 
		WHEN m.home_goals>m.visitor_goals THEN '1'
		WHEN m.home_goals<m.visitor_goals THEN '2'
		ELSE 'x' 
	END AS resultado

FROM euro2021.tb_match m

INNER JOIN euro2021.tb_team h
		ON m.home_team_code = h.team_code

INNER JOIN euro2021.tb_team v
		ON m.visitor_team_code = v.team_code

INNER JOIN euro2021.tb_country c1
		ON h.country_code = c1.country_code

INNER JOIN euro2021.tb_country c2
		ON v.country_code = c2.country_code

INNER JOIN euro2021.tb_referee r
		ON m.referee_code = r.referee_code

INNER JOIN euro2021.tb_phase p
		ON m.phase_code = p.phase_code

ORDER BY m.match_date, r.referee_name
;



-- Now we want a list of all cities (city name and country name), the total different referees that have judged a match in that city,
--the sum of the goals in the city.
--We want to include cities where no match has taken place and will show the result as 0 instead of Null.

SELECT 
		c.country_name,
		ci.city_name,
		COUNT (DISTINCT m.referee_code) as num_refs,		
		SUM (COALESCE (m.home_goals+m.visitor_goals,0)) AS total_goals		
FROM euro2021.tb_match m

RIGHT JOIN euro2021.tb_stadium s
		ON m.tb_city = s.tb_city

RIGHT JOIN euro2021.tb_city ci
		ON s.city_code = ci.city_code and s.country_code = ci.country_code

JOIN euro2021.tb_country c
		ON ci.country_code = c.country_code

GROUP BY 	ci.city_name,
			c.country_name
		
ORDER BY 	num_refs DESC, 
			city_name
;



-- We want the name and code for all counties and the total of matches, yellow and red cards shown in the matches, 
-- the avg of cards (red+yellow). We must show all countries including the ones where no match took place and show results as 0 instead of null.
-- We need to consider that some countries may have more than 1 stadium.


SELECT 
	c.country_name,
	c.country_code,
	COUNT (m.*) AS num_games,
	SUM (COALESCE (m.home_yellow_cards+m.visitor_yellow_cards,0)) AS num_yellow_cards,
	SUM (COALESCE (m.home_red_cards+m.visitor_red_cards,0)) AS num_red_cards,
	COALESCE (round (AVG (m.home_yellow_cards+m.visitor_yellow_cards+m.home_red_cards+m.visitor_red_cards),2),0) AS avg_cards
FROM euro2021.tb_match AS m

INNER JOIN euro2021.tb_stadium s
		ON m.stadium_code = s.stadium_code

RIGHT JOIN euro2021.tb_country c
		ON s.country_code = c.country_code
		
INNER JOIN euro2021.tb_city ci	
	ON s.city_code = ci.city_code

GROUP BY c.country_name, 
		 c.country_code

ORDER BY num_games DESC, 
		 avg_cards, 
		 country_name;



-- We want the name and countries for the referees that have judged a match in 'Round of 16' 
--and belong to a country that played (as local or visitor) also in the same phase


SELECT 
	DISTINCT (r.referee_code),
	r.referee_name,
	c.country_name AS country_ref

FROM euro2021.tb_match m

JOIN euro2021.tb_referee r
		ON m.referee_code = r.referee_code

JOIN euro2021.tb_phase p
		ON m.phase_code= p.phase_code

JOIN euro2021.tb_country c
		ON r.country = c.country_code

WHERE p.phase_name = 'Round of 16'
	AND r.country IN 
	(SELECT 
	 t.country_code
	 FROM  euro2021.tb_match m

	JOIN euro2021.tb_team t
		ON m.home_team_code = t.team_code

	JOIN euro2021.tb_country c
		ON t.country_code = c.country_code

	JOIN euro2021.tb_phase p
		ON m.phase_code = p.phase_code

	WHERE p.phase_name = 'Round of 16'

	UNION

	SELECT 
	t.country_code
	FROM euro2021.tb_match m

	JOIN euro2021.tb_team t
		ON m.visitor_team_code = t.team_code

	JOIN euro2021.tb_country c
		ON t.country_code = c.country_code

	JOIN euro2021.tb_phase p
	ON m.phase_code = p.phase_code
	 
	WHERE p.phase_name = 'Round of 16')

ORDER BY referee_name
;


-- Now we are going to create a new databse, schem and 2 new tables:

CREATE DATABASE uefa_pec2;

CREATE SCHEMA euro2021_dw;

CREATE TABLE uefa_pec2.euro2021_dw.tb_match_by_city_agg(
	city_code CHAR(5) NOT NULL,
	city_name VARCHAR (60) NOT NULL,
	country_code VARCHAR (40) NOT NULL,
	country_name VARCHAR (60) NOT NULL,
	referee_count INTEGER NOT NULL,
	goal_count INTEGER NOT NULL,
	PRIMARY KEY (city_code,country_code)
);


CREATE TABLE uefa_pec2.euro2021_dw.tb_match_by_phase_agg(
	phase_code CHAR(5) NOT NULL,
	phase_name VARCHAR (40) NOT NULL,
	match_count INTEGER NOT NULL,
	goal_avg NUMERIC (4,2) NOT NULL,
	stadium_count INTEGER NOT NULL,
	PRIMARY KEY (phase_code)
);


-- Now we are going to create a PL/SQL procedure to store data in the new tables that we have created tb_match_by_city_agg and tb_match_by_phase_agg.
-- We are creating a procedure called sp_load_match_by_city_agg that will store date in the table tb_match_by_city_agg.
-- This procedure will obtain the city information from the previous existing table and schema.
-- We need to delete first all contents from the table tb_match_by_city_agg.


BEGIN WORK;

CREATE OR REPLACE FUNCTION euro2021_dw.sp_load_match_by_city_agg()
RETURNS void 
AS $$
DECLARE 
	v_row_match_agg euro2021_dw.tb_match_by_city_agg%rowtype; 
BEGIN
		RAISE INFO 'Iniciando la carga de la tabla de agregados ...';

	DELETE FROM uefa_pec2.euro2021_dw.tb_match_by_city_agg;
	FOR v_row_match_agg IN 

	SELECT 
		ci.city_code,
		ci.city_name,
		c.country_code,
		c.country_name,
		COUNT (DISTINCT m.referee_code) 
			AS referee_count,
		SUM (COALESCE (m.home_goals+m.visitor_goals,0)) 
			AS goal_count

	FROM euro2021.tb_match m

	RIGHT JOIN euro2021.tb_stadium s
		ON m.stadium_code = s.stadium_code

	RIGHT JOIN euro2021.tb_city ci
		ON s.city_code = ci.city_code and s.country_code=ci.country_code

	JOIN euro2021.tb_country c
		ON ci.country_code = c.country_code

	GROUP BY 
		ci.city_code, 
		ci.city_name,
		c.country_code, 
		c.country_name
	ORDER BY referee_count DESC

	LOOP

	INSERT INTO uefa_pec2.euro2021_dw.tb_match_by_city_agg 
		SELECT v_row_match_agg.*;

	END LOOP; 
	
   		RAISE INFO 'Finalizada la carga de la tabla de agregados.';

END;

$$ LANGUAGE plpgsql;


--With the following case we call the procedure:
SELECT euro2021_dw.sp_load_match_by_city_agg();
-- And with this query we can check if the data was correctly loaded:
SELECT * FROM euro2021_dw.tb_match_by_city_agg;


--New PL/SQL procedure to store data in the new table tb_match_by_phase_agg
-- We are going to load in this table the phase details from the already existing table.
-- We will first delete any content on table tb_match_by_phase_agg

BEGIN WORK;

CREATE OR REPLACE FUNCTION euro2021_dw.sp_load_match_by_phase_agg()
RETURNS void 
AS $$
DECLARE 
	v_row_phase_agg euro2021_dw.tb_match_by_phase_agg%rowtype;
BEGIN
		RAISE INFO 'Iniciando la carga de la tabla de agregados ...';

	DELETE FROM uefa_pec2.euro2021_dw.tb_match_by_phase_agg;
	FOR v_row_phase_agg IN 

	SELECT 
		m.phase_code,
		p.phase_name,
		COUNT (m.phase_code) as match_count,
		ROUND(AVG (m.home_goals+m.visitor_goals),2) as goal_avg,
		COUNT (distinct m.stadium_code) as stadium_count

	FROM euro2021.tb_match m

	JOIN euro2021.tb_phase p
		ON m.phase_code=p.phase_code

	GROUP BY m.phase_code, p.phase_name
	ORDER BY goal_avg desc

	LOOP
	INSERT INTO uefa_pec2.euro2021_dw.tb_match_by_phase_agg 
		SELECT v_row_phase_agg.*;

	END LOOP; 
    	RAISE INFO 'Finalizada la carga de la tabla de agregados';
	
END;

$$ LANGUAGE plpgsql;

-- We will call now the procedure:
SELECT euro2021_dw.sp_load_match_by_phase_agg();
-- And will check if the data has been stored:
SELECT * FROM euro2021_dw.tb_match_by_phase_agg;




