// src/client_ffi.mjs
export function listen_to_sse(url, dispatch) {
  const source = new EventSource(url);

  source.onmessage = (event) => {
    // This calls the 'dispatch' function provided by Lustre
    dispatch(event.data);
  };

  // Optional: handle errors or close connection
  return () => source.close();
}
