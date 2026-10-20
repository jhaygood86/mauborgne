namespace Mauborgne.Threads {

    public delegate void BlockingWork () throws Error;

    /**
     * Runs work on a separate thread and resumes when it is done, so the key stretching
     * (deliberately slow) does not freeze the window. An error thrown by the work is rethrown here.
     */
    public async void run_blocking (owned BlockingWork work) throws Error {
        Error? failure = null;
        SourceFunc resume = run_blocking.callback;

        var thread = new Thread<bool> ("mauborgne-cloud", () => {
            try {
                work ();
            } catch (Error e) {
                failure = e;
            }

            Idle.add ((owned) resume);
            return true;
        });

        yield;
        thread.join ();

        if (failure != null) {
            throw failure;
        }
    }
}
