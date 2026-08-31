-- 1. PostGIS Extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Profiles Table (User & Mama)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  avatar_url TEXT,
  sharing_on BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Friendships / Family Links Table
CREATE TABLE IF NOT EXISTS public.friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_a UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_id_b UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT unique_friendship UNIQUE (user_id_a, user_id_b),
  CONSTRAINT check_user_order CHECK (user_id_a < user_id_b)
);

-- 4. Live User Locations Table
CREATE TABLE IF NOT EXISTS public.user_locations (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  accuracy REAL,
  heading REAL,
  battery SMALLINT CHECK (battery BETWEEN 0 AND 100),
  is_mocked BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_locations ENABLE ROW LEVEL SECURITY;

-- 6. Policies
CREATE POLICY "Allow authenticated read profiles"
  ON public.profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow user update own profile"
  ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);

CREATE POLICY "Allow user insert own profile"
  ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Allow authenticated read friendships"
  ON public.friendships FOR SELECT TO authenticated
  USING (auth.uid() = user_id_a OR auth.uid() = user_id_b);

CREATE POLICY "Allow authenticated insert friendships"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id_a OR auth.uid() = user_id_b);

CREATE POLICY "Allow authenticated delete friendships"
  ON public.friendships FOR DELETE TO authenticated
  USING (auth.uid() = user_id_a OR auth.uid() = user_id_b);

CREATE POLICY "Allow authenticated read locations"
  ON public.user_locations FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow user upsert own location"
  ON public.user_locations FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 7. Trigger to automatically create profile on sign up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 8. Realtime Publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.friendships;

-- 9. Storage bucket for profile avatars
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Avatar public view"
  ON storage.objects FOR SELECT TO public USING (bucket_id = 'avatars');

CREATE POLICY "Avatar authenticated upload"
  ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "Avatar authenticated update"
  ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'avatars');
