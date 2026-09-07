-- 078_device_model.sql
-- v0.8.1: "Angemeldete Geraete" zeigt das ECHTE Geraetemodell
-- (z. B. "Samsung SM-S921B", "Nothing A063") statt nur "Android (SDK 34)".
-- Nach einer Neuinstallation erhaelt man sonst ein unlesbares "neues
-- Geraet", obwohl es dasselbe Handy ist.

alter table public.auth_devices
  add column if not exists device_model text;

comment on column public.auth_devices.device_model is
'Vom Geraet selbst gemeldetes Modell (Hersteller + Modellkennung, client-gesetzt).';

-- Laengen-Constraint um device_model erweitern (idempotent).
alter table public.auth_devices
  drop constraint if exists chk_auth_devices_model_len;

alter table public.auth_devices
  add constraint chk_auth_devices_model_len
  check (device_model is null or char_length(device_model) <= 80)
  not valid;

alter table public.auth_devices
  validate constraint chk_auth_devices_model_len;
