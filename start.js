module.exports = {
  daemon: true,
  run: [
    {
      method: "shell.run",
      params: {
        venv: "env",
        env: {
          GRADIO_SERVER_NAME: "127.0.0.1"
        },
        path: "app",
        message: {
          _: [
            "python",
            "../launch.py",
            "--model",
            "{{args.model ? args.model : 'small-music'}}",
            "--title",
            "{{args.title ? args.title : 'Stable Audio 3 Small Music'}}",
            "--default-prompt",
            "{{args.prompt ? args.prompt : 'lo-fi hip hop beat, 90 BPM'}}"
          ]
        },
        on: [{
          event: "/(http:\\/\\/[0-9.:]+)/",
          done: true
        }]
      }
    },
    {
      method: "local.set",
      params: {
        url: "{{input.event[1]}}"
      }
    }
  ]
}
