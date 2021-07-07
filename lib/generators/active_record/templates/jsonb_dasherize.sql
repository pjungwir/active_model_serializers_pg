CREATE FUNCTION jsonb_dasherize(j jsonb)
RETURNS jsonb
IMMUTABLE
AS
$$
DECLARE
t text;
ret jsonb;
BEGIN
  t := jsonb_typeof(j);
  IF t = 'object' THEN
    SELECT  COALESCE(jsonb_object_agg(replace(lower(regexp_replace(k, '([A-Z])', '_\1', 'g')), '_', '-'), jsonb_dasherize(v)), '{}')
    INTO    ret
    FROM    jsonb_each(j) AS t(k, v);
    RETURN ret;
  ELSIF t = 'array' THEN
    SELECT  COALESCE(jsonb_agg(jsonb_dasherize(elem)), '[]')
    INTO    ret
    FROM    jsonb_array_elements(j) AS t(elem);
    RETURN ret;
  ELSIF t IS NULL THEN
    -- This should never happen internally
    -- (thankfully, lest jsonb_set return NULL and destroy everything),
    -- but only from a passed-in NULL.
    RETURN NULL;
  ELSE
    -- string/number/null:
    RETURN j;
  END IF;
END;
$$
LANGUAGE plpgsql;
