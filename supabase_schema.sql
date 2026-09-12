-- ==========================================
-- TEACHERS TABLE
-- ==========================================

CREATE TABLE IF NOT EXISTS public.teachers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  subject text NOT NULL,
  category text NOT NULL DEFAULT 'all',
  initials text,
  bio text,
  rating numeric(2,1) NOT NULL DEFAULT 0,
  review_count integer NOT NULL DEFAULT 0,
  recommend_percent integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);


-- ==========================================
-- ДОБАВЛЯЕМ НЕДОСТАЮЩИЕ КОЛОНКИ
-- ==========================================

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS name text;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS subject text;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS category text DEFAULT 'all';

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS initials text;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS bio text;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS rating numeric(2,1) DEFAULT 0;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS review_count integer DEFAULT 0;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS recommend_percent integer DEFAULT 0;

ALTER TABLE public.teachers
ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();


-- ==========================================
-- ДОБАВЛЯЕМ УЧИТЕЛЕЙ
-- ==========================================

INSERT INTO public.teachers
(name, subject, category, initials, bio)
SELECT
  v.name,
  v.subject,
  v.category,
  v.initials,
  v.bio
FROM (
  VALUES
    (
      'Анна Кузнецова',
      'Математика',
      'math',
      'АК',
      'Объясняет сложные темы простым языком и помогает уверенно готовиться к контрольным.'
    ),
    (
      'Дмитрий Смирнов',
      'Информатика',
      'science',
      'ДС',
      'Практика, проекты и современные задачи. Делает акцент на понимании, а не на зубрёжке.'
    ),
    (
      'Елена Петрова',
      'Русский язык',
      'languages',
      'ЕП',
      'Требовательная и внимательная. Помогает прокачать письменную речь и подготовиться к экзаменам.'
    ),
    (
      'Максим Иванов',
      'Физика',
      'science',
      'МИ',
      'Эксперименты, наглядные примеры и разбор реальных задач.'
    ),
    (
      'Ольга Волкова',
      'История',
      'humanities',
      'ОВ',
      'Дискуссии, кейсы и живые исторические сюжеты вместо сухого пересказа.'
    ),
    (
      'Сергей Никитин',
      'Английский язык',
      'languages',
      'СН',
      'Много разговорной практики, понятная грамматика и полезные материалы.'
    )
) AS v(name, subject, category, initials, bio)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.teachers t
  WHERE t.name = v.name
);


-- ==========================================
-- RLS
-- ==========================================

ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS teachers_read ON public.teachers;

CREATE POLICY teachers_read
ON public.teachers
FOR SELECT
USING (true);
