-- プライベートのログは1人に1つだけにする。
-- ensurePrivateLog は「探して、無ければ作る」なので、同時に呼ばれると2つできる。
-- DB側で止めて、競合したほうは既にあるものを使う。
CREATE UNIQUE INDEX IF NOT EXISTS idx_logs_private_owner ON logs(owner_id) WHERE kind = 'private';
