type UmaskSetter = (mask?: number) => number;

export function acquirePrivateUmask(
  mask: number,
  setter: UmaskSetter = process.umask,
  environment = process.env.NODE_ENV,
): () => void {
  try {
    const previous = setter(mask);
    return () => { setter(previous); };
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (environment === "test" && code === "ERR_WORKER_UNSUPPORTED_OPERATION") {
      return () => undefined;
    }
    throw error;
  }
}
