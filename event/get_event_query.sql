-- Get events with parameters in json
SELECT event.id,
       event.title,
       event.dt_start,
       event.dt_end,
       json_object_agg(UPPER(name), UPPER(parameter_value)) ->> 0 as parameters
FROM event
         LEFT JOIN (pattern pat LEFT JOIN parameters par on pat.parameter_id = par.id) as params
                   on event.id = params.event_id and event.calendar_id = params.calendar_id
WHERE name IS NOT NULL
GROUP BY event.id, event.calendar_id;

SELECT event.id,
       event.title,
       event.dt_start,
       event.dt_end,
       STRING_AGG(UPPER(name) || '=' || UPPER(parameter_value), ';') as parameters
FROM event
         LEFT JOIN (pattern pat LEFT JOIN parameters par on pat.parameter_id = par.id) as params
                   on event.id = params.event_id and event.calendar_id = params.calendar_id
WHERE name IS NOT NULL
GROUP BY event.id, event.calendar_id;

SELECT sq.id                     as e_id,
       sq.title                  as e_title,
       sq.dt_start               as e_dt_start,
       sq.dt_start + sq.duration as e_dt_end
FROM (
         SELECT event.id,
                event.title,
                unnest(get_occurrences(STRING_AGG(UPPER(name) || '=' || UPPER(parameter_value), ';')::text,
                                       event.dt_start, event.dt_end)) as
                                                                         dt_start,
                event.duration                                        as duration
         FROM event
                  LEFT JOIN (pattern pat LEFT JOIN parameters par on pat.parameter_id = par.id) as params
                            on event.id = params.event_id and event.calendar_id = params.calendar_id
         WHERE name IS NOT NULL
         GROUP BY event.id, event.calendar_id) as sq;

-- Get users and calendars
SELECT username, c.id calendar_id, c.title, c.description
FROM users
         LEFT JOIN users_calendar uc on users.id = uc.user_id
         LEFT JOIN calendar c on uc.calendar_id = c.id;
-- STRING_AGG(UPPER(json_obj->1) || '=' || UPPER(json_obj->2), ';')::text
DROP FUNCTION get_rrule_from_json(jsonb);
CREATE OR REPLACE FUNCTION get_rrule_from_json(rrule jsonb)
    RETURNS text
    LANGUAGE plpgsql
AS
$Body$
BEGIN
    RETURN (SELECT STRING_AGG(UPPER(jsn.key) || '=' || UPPER(jsn.value), ';')::text
            FROM (SELECT 1 as grouper, * FROM jsonb_each_text(rrule)) as jsn
            GROUP BY grouper);
END;
$Body$;

DROP FUNCTION get_events_from_range(integer, integer, timestamp without time zone, timestamp without time zone);

CREATE OR REPLACE FUNCTION get_events_from_range(
    user_id integer,
    calendar_id integer,
    frame_dt_start timestamp,
    frame_dt_end timestamp
)
    RETURNS TABLE
            (
                e_id          integer,
                e_calendar_id integer,
                e_title       text,
                e_dt_start    timestamp,
                e_dt_end      timestamp
            )
    LANGUAGE plpgsql
AS
$Body$
DECLARE
    user_id alias for $1;
    calendar_id alias for $2;
    frame_dt_start alias for $3;
    frame_dt_end alias for $4;

BEGIN
    -- Check if a calendar is available to a user
    PERFORM check_user_calendar(user_id, calendar_id);

    RETURN QUERY SELECT events.*
                 FROM (SELECT sq.id                     as e_id,
                              calendar_id               as e_calendar_id,
                              sq.title                  as e_title,
                              sq.dt_start               as e_dt_start,
                              sq.dt_start + sq.duration as e_dt_end
                       FROM (
                                SELECT event.id,
                                       event.title,
                                       unnest(get_occurrences(
                                               STRING_AGG(UPPER(name) || '=' || UPPER(parameter_value), ';')::text,
                                               event.dt_start, event.dt_end)) as
                                                                                 dt_start,
                                       event.duration                         as duration
                                FROM event
                                         LEFT JOIN (pattern pat LEFT JOIN parameters par on pat.parameter_id = par.id) as params
                                                   on event.id = params.event_id and event.calendar_id = params.calendar_id
                                WHERE name IS NOT NULL
                                GROUP BY event.id, event.calendar_id) as sq) as events
                 WHERE events.e_dt_start NOT IN (SELECT dt_start
                                                 FROM exception_event as ex_e
                                                 WHERE ex_e.event_id = events.e_id
                                                   AND ex_e.calendar_id = events.e_calendar_id);
END ;
$Body$;

SELECT *
FROM get_events_from_range(1, 1, '2019-01-01 11:00'::timestamp, '2022-12-06 23:30'::timestamp);