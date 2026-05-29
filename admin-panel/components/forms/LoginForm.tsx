'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { toast } from 'sonner';
import { Eye, EyeOff, Loader2, LogIn } from 'lucide-react';
import { ApiError, authApi } from '@/lib/api';
import { setStoredUser, setToken, isAuthenticated } from '@/lib/auth';
import { loginSchema } from '@/lib/validators';
import { Field, Input, Label } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get('next') || '/dashboard';

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});

  useEffect(() => {
    if (isAuthenticated()) {
      router.replace(next);
    }
  }, [next, router]);

  async function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    const parsed = loginSchema.safeParse({ email: username, password });
    if (!parsed.success) {
      const flat = parsed.error.flatten().fieldErrors;
      setErrors({
        email: flat.email?.[0],
        password: flat.password?.[0],
      });
      return;
    }
    setErrors({});
    setLoading(true);
    try {
      const res = await authApi.login(parsed.data.email, parsed.data.password);
      setToken(res.token);
      setStoredUser(res.user);
      toast.success(`Welcome back, ${res.user.name || res.user.email}`);
      router.replace(next.startsWith('/login') ? '/dashboard' : next);
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : err instanceof Error
            ? err.message
            : 'Login failed';
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <form
      onSubmit={onSubmit}
      className="w-full max-w-md rounded-2xl border border-line bg-panel/70 p-7 shadow-2xl backdrop-blur-xl"
    >
      <div className="mb-7">
        <div className="mb-3 grid h-12 w-12 place-items-center rounded-xl bg-gradient-to-br from-cyan-300 to-cyan-500 font-black text-slate-950 shadow-glow">
          CP
        </div>
        <h1 className="text-2xl font-semibold text-white">CricPro Admin</h1>
        <p className="mt-2 text-sm text-slate-400">
          Sign in to manage streams, providers, settings, cache, and live app
          controls.
        </p>
      </div>

      <div className="space-y-4">
        <Field label="Username" required error={errors.email}>
          <Input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            type="text"
            autoComplete="username"
            placeholder="Enter admin username"
            invalid={!!errors.email}
          />
        </Field>

        <div>
          <Label required>Password</Label>
          <div className="relative">
            <Input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
              placeholder="••••••••"
              invalid={!!errors.password}
              className="pr-10"
            />
            <button
              type="button"
              onClick={() => setShowPassword((s) => !s)}
              className="absolute right-2 top-1/2 grid h-7 w-7 -translate-y-1/2 place-items-center rounded-md text-slate-400 hover:bg-white/5 hover:text-white"
              aria-label={showPassword ? 'Hide password' : 'Show password'}
            >
              {showPassword ? (
                <EyeOff className="h-4 w-4" />
              ) : (
                <Eye className="h-4 w-4" />
              )}
            </button>
          </div>
          {errors.password && (
            <p className="mt-1 text-xs text-red-300">{errors.password}</p>
          )}
        </div>
      </div>

      <Button
        type="submit"
        loading={loading}
        icon={loading ? null : <LogIn className="h-4 w-4" />}
        className="mt-6 w-full"
      >
        {loading ? 'Signing in…' : 'Sign in'}
      </Button>

      <p className="mt-4 text-center text-xs text-slate-500">
        Secured by JWT access tokens + httpOnly refresh cookies. Failed sign-ins
        are rate-limited.
      </p>
    </form>
  );
}
