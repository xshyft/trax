-- PostgreSQL initialization script for Agora development environment
-- This script creates the 

-- Connect to the agora_db database
\c agora_db;

-- Create schemas for different components
CREATE SCHEMA IF NOT EXISTS trax;

-- Show current database info
SELECT current_database() as database_name, current_user as current_user, version() as postgresql_version;

-- List all databases
\l

-- List all users to confirm
\echo 'All PostgreSQL users:'
\du

-- Step 3: Create Trax saga orchestration tables
-- Create saga templates table in trax schema
CREATE TABLE IF NOT EXISTS trax.saga_templates (
	template_id VARCHAR PRIMARY KEY,
	display_name VARCHAR NOT NULL,
	description TEXT,
	labels JSONB NOT NULL DEFAULT '{}',
	tags JSONB NOT NULL DEFAULT '[]',
	metadata JSONB NOT NULL DEFAULT '{}',
	saga_step_template_ids JSONB NOT NULL DEFAULT '[]',
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create saga step templates table in trax schema
CREATE TABLE IF NOT EXISTS trax.saga_step_templates (
	template_id VARCHAR PRIMARY KEY,
	saga_template_id VARCHAR NOT NULL,
	display_name VARCHAR NOT NULL,
	description TEXT,
	labels JSONB NOT NULL DEFAULT '{}',
	tags JSONB NOT NULL DEFAULT '[]',
	metadata JSONB NOT NULL DEFAULT '{}',
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY (saga_template_id) REFERENCES trax.saga_templates(template_id)
);

-- Create clusters table in trax schema
CREATE TABLE IF NOT EXISTS trax.clusters (
	id VARCHAR PRIMARY KEY,
	display_name VARCHAR NOT NULL,
	description TEXT,
	labels JSONB NOT NULL DEFAULT '{}',
	tags JSONB NOT NULL DEFAULT '[]',
	metadata JSONB NOT NULL DEFAULT '{}',
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

\echo 'Trax saga orchestration tables created successfully!'

