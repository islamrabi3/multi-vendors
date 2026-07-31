-- Migration: Add FCM Tokens & Proof of Delivery to Database Schema
-- File: 20260727010000_push_notifications.sql

-- 1. Add fcm_token column to profiles table to store device push tokens
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token text;

-- 2. Add proof_image_url column to orders table for Driver Proof of Delivery photos
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS proof_image_url text;

-- 3. Create index for fast FCM token lookup by profile ID
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token ON public.profiles (id, fcm_token);
