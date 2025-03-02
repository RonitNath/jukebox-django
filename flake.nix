{
  description = "OCF Jukebox Django Application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pythonEnv = pkgs.python311.withPackages (ps: with ps; [
          django
          yt-dlp
          jsonpickle
          wheel
          pyaudio
          websockets
          aioconsole
          channels
          daphne
          pip
          poetry
        ]);

        # Create a custom derivation for the jukebox app
        jukebox-django = pkgs.stdenv.mkDerivation {
          pname = "jukebox-django";
          version = "0.1.0";
          src = ./.;

          buildInputs = [
            pythonEnv
            pkgs.portaudio
            pkgs.poetry
          ];

          # No build phase, just install the files
          dontBuild = true;

          installPhase = ''
            mkdir -p $out/share/jukebox-django
            cp -r . $out/share/jukebox-django

            # Create a wrapper script to run the Django server
            mkdir -p $out/bin
            cat > $out/bin/jukebox-django-server << EOF
            #!/bin/sh
            cd $out/share/jukebox-django
            ${pkgs.poetry}/bin/poetry run python jukebox/manage.py runserver "\$@"
            EOF

            # Create a wrapper script to run the backend
            cat > $out/bin/jukebox-django-backend << EOF
            #!/bin/sh
            cd $out/share/jukebox-django
            ${pkgs.poetry}/bin/poetry run python jukebox/backend/runner.py "\$@"
            EOF

            # Create a setup script
            cat > $out/bin/jukebox-django-setup << EOF
            #!/bin/sh
            cd $out/share/jukebox-django
            if [ ! -f pyproject.toml ]; then
              echo "Initializing Poetry project..."
              ${pkgs.poetry}/bin/poetry init --no-interaction \\
                --name jukebox-django \\
                --description "OCF Jukebox Django Application" \\
                --author "OCF" \\
                --python ">=3.11,<3.12"
              
              # Add required dependencies to Poetry
              ${pkgs.poetry}/bin/poetry add django yt-dlp jsonpickle wheel pyaudio websockets aioconsole channels daphne django-icons==24.4
            fi
            
            # Install all dependencies
            ${pkgs.poetry}/bin/poetry install
            EOF

            chmod +x $out/bin/jukebox-django-server
            chmod +x $out/bin/jukebox-django-backend
            chmod +x $out/bin/jukebox-django-setup
          '';

          # Ensure Python can find portaudio
          fixupPhase = ''
            wrapProgram $out/bin/jukebox-django-server \\
              --prefix LD_LIBRARY_PATH : ${pkgs.portaudio}/lib \\
              --prefix PYTHONPATH : $PYTHONPATH

            wrapProgram $out/bin/jukebox-django-backend \\
              --prefix LD_LIBRARY_PATH : ${pkgs.portaudio}/lib \\
              --prefix PYTHONPATH : $PYTHONPATH
          '';

          nativeBuildInputs = [ 
            pkgs.makeWrapper
          ];
        };
      in
      {
        packages = {
          default = jukebox-django;
          jukebox-django = jukebox-django;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            (python311.withPackages (ps: with ps; [
              django
              yt-dlp
              jsonpickle
              wheel
              pyaudio
              websockets
              aioconsole
              channels
              daphne
              pip
              poetry-core
            ]))
            portaudio
            poetry
            ffmpeg
          ];

          shellHook = ''
            # Set up environment variables if needed
            export PYTHONPATH=$PWD:$PYTHONPATH
            export LD_LIBRARY_PATH=${pkgs.portaudio}/lib:$LD_LIBRARY_PATH
            
            # Check for a pyproject.toml file, create one if it doesn't exist
            if [ ! -f pyproject.toml ]; then
              echo "Initializing Poetry project..."
              poetry init --no-interaction \
                --name jukebox-django \
                --description "OCF Jukebox Django Application" \
                --author "OCF" \
                --python ">=3.11,<3.12"
              
              # Add required dependencies to Poetry
              poetry add django yt-dlp jsonpickle wheel pyaudio websockets aioconsole channels daphne django-icons==24.4
            fi
            
            # Install dependencies from Poetry
            poetry install
            
            # Activate the Poetry shell
            # This ensures we're using Poetry's environment
            poetry shell --no-interaction || true
            
            # Note for users
            echo "Nix development environment for jukebox-django activated!"
            echo "Poetry environment is active with all dependencies installed."
            echo "To run the backend server: cd jukebox/backend && python runner.py"
            echo "To run the Django server: cd jukebox && python manage.py runserver"
          '';
        };
      });
} 