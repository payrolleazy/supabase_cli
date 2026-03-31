create index if not exists idx_platform_actor_role_grant_role_code
on public.platform_actor_role_grant (role_code);

create index if not exists idx_platform_membership_invitation_role_code
on public.platform_membership_invitation (role_code);

create index if not exists idx_platform_signup_request_invitation_id
on public.platform_signup_request (invitation_id);

create index if not exists idx_platform_signup_request_async_job_id
on public.platform_signup_request (async_job_id);

create index if not exists idx_platform_signin_challenge_policy_code
on public.platform_signin_challenge (policy_code);
