DO $$
DECLARE
  esquema TEXT := '{{esquema}}';
  tabla TEXT := '{{tabla}}';
  hay_duplicados BOOLEAN := FALSE;
  hay_nulas BOOLEAN := FALSE;
  hay_invalidas BOOLEAN := FALSE;
  sql TEXT;
BEGIN
  -- Verificar geometrías duplicadas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I a
      JOIN %I.%I b
        ON a.ctid <> b.ctid AND ST_Equals(a.geom, b.geom)
      LIMIT 1
    )
  $f$, esquema, tabla, esquema, tabla);
  EXECUTE sql INTO hay_duplicados;

  -- Verificar geometrías nulas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I
      WHERE geom IS NULL
      LIMIT 1
    )
  $f$, esquema, tabla);
  EXECUTE sql INTO hay_nulas;

  -- Verificar geometrías inválidas
  sql := format($f$
    SELECT EXISTS (
      SELECT 1 FROM %I.%I
      WHERE NOT ST_IsValid(geom)
      LIMIT 1
    )
  $f$, esquema, tabla);
  EXECUTE sql INTO hay_invalidas;

  -- Resultados
  IF hay_duplicados THEN
    RAISE NOTICE '⚠ Existen geometrías duplicadas en %I.%I.', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías duplicadas.';
  END IF;

  IF hay_nulas THEN
    RAISE NOTICE '⚠ Existen geometrías nulas en %I.%I.', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías nulas.';
  END IF;

  IF hay_invalidas THEN
    RAISE NOTICE '⚠ Existen geometrías inválidas en %I.%I.', esquema, tabla;
  ELSE
    RAISE NOTICE '✅ No se encontraron geometrías inválidas.';
  END IF;
END$$;
