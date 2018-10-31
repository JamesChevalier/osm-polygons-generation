CREATE TABLE polygons (
    id integer NOT NULL,
    params character varying(40) NOT NULL,
    "timestamp" timestamp without time zone,
    geom public.geometry
);
ALTER TABLE ONLY polygons ADD CONSTRAINT polygons_pkey PRIMARY KEY (id, params);

CREATE TABLE polygons_user (
    name character varying(40) NOT NULL,
    "timestamp" timestamp without time zone,
    geom public.geometry
);
ALTER TABLE ONLY polygons_user ADD CONSTRAINT polygons_user_pkey PRIMARY KEY (name);

CREATE TABLE relations (
    id integer NOT NULL,
    tags hstore
);
ALTER TABLE ONLY relations ADD CONSTRAINT relations_pkey PRIMARY KEY (id);


CREATE OR REPLACE FUNCTION ends(linestring geometry) RETURNS SETOF geometry AS $$
DECLARE BEGIN
    RETURN NEXT ST_PointN(linestring,1);
    RETURN NEXT ST_PointN(linestring,ST_NPoints(linestring));
    RETURN;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_polygon(rel_id integer) RETURNS integer
AS $BODY$
DECLARE
  line RECORD;
  ok boolean;
BEGIN
  DELETE FROM polygons WHERE id = rel_id;

  DROP TABLE IF EXISTS tmp_way_poly;

  -- recup des way des relations
  CREATE TEMP TABLE tmp_way_poly AS
  WITH RECURSIVE deep_relation(id) AS (
        SELECT
            rel_id::bigint AS member_id
    UNION
        SELECT
            relation_members.member_id
        FROM
            deep_relation
            JOIN relation_members ON
                relation_members.relation_id = deep_relation.id AND
                relation_members.member_type = 'R' AND
                relation_members.member_role != 'subarea' AND
                relation_members.member_role != 'land_area'
  )
  SELECT DISTINCT ON (ways.id)
    ways.linestring, ways.id
  FROM
    deep_relation
    JOIN relation_members ON
        relation_members.relation_id = deep_relation.id AND
        relation_members.member_type = 'W'
    JOIN ways ON
        ways.id = relation_members.member_id
  ;

  SELECT INTO ok 't';

  FOR line in SELECT
             ST_X(geom) AS x, ST_Y(geom) AS y, string_agg(id::varchar(255), ' ') AS id
           FROM
             (SELECT ends(linestring) AS geom, id FROM tmp_way_poly) AS d
           GROUP BY
             geom
           HAVING
             COUNT(*) != 2
  LOOP
    SELECT INTO ok 'f';
    RAISE NOTICE 'missing connexion at point %f %f - ways: %', line.x, line.y, line.id;
  END LOOP;

  INSERT INTO polygons
  VALUES (rel_id,
          '0',
          NOW(),
          (SELECT st_collect(st_makepolygon(geom))
           FROM (SELECT (st_dump(st_linemerge(st_collect(d.linestring)))).geom
                 FROM (SELECT DISTINCT(linestring) AS linestring
                        FROM tmp_way_poly) as d
                ) as c
         ));

  RETURN st_npoints(geom) FROM polygons WHERE id = rel_id;
END
$BODY$
LANGUAGE 'plpgsql' ;

CREATE OR REPLACE FUNCTION create_polygon2(rel_id integer) RETURNS integer
AS $BODY$
DECLARE
  line RECORD;
  ok boolean;
BEGIN
  DELETE FROM polygons WHERE id = rel_id;

  DROP TABLE IF EXISTS tmp_way_poly;

  -- recup des way des relations
  EXECUTE format('CREATE TEMP TABLE tmp_way_poly AS
    SELECT * FROM "tmp_way_poly_%s"', rel_id);

  EXECUTE format('DROP TABLE "tmp_way_poly_%s"', rel_id);

  SELECT INTO ok 't';

  FOR line in SELECT
             ST_X(geom) AS x, ST_Y(geom) AS y, string_agg(id::varchar(255), ' ') AS id
           FROM
             (SELECT ends(linestring) AS geom, id FROM tmp_way_poly) AS d
           GROUP BY
             geom
           HAVING
             COUNT(*) != 2
  LOOP
    SELECT INTO ok 'f';
    RAISE NOTICE 'missing connexion at point %f %f - ways: %', line.x, line.y, line.id;
  END LOOP;

  INSERT INTO polygons
  VALUES (rel_id,
          '0',
          NOW(),
          (SELECT st_collect(st_makepolygon(geom))
           FROM (SELECT (st_dump(st_linemerge(st_collect(d.linestring)))).geom
                 FROM (SELECT DISTINCT(linestring) AS linestring
                        FROM tmp_way_poly) as d
                ) as c
         ));
  UPDATE polygons SET geom = ST_SetSRID(geom, 4326) WHERE id = rel_id;

  RETURN st_npoints(geom) FROM polygons WHERE id = rel_id;
END
$BODY$
LANGUAGE 'plpgsql' ;

