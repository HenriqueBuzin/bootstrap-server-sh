pipeline {
    agent any

    stages {

        stage('Deploy') {
            steps {
                script {

                    def branch = env.GIT_BRANCH.replace("origin/", "")
                    def project = "bootstrap-server-sh"

                    echo "Branch: ${branch}"

                    if (branch == 'main') {
                        sh """
                        cd /root/projects/${project}

                        git fetch origin
                        git reset --hard origin/main
                        git clean -fd

                        ln -sf /root/envs/${project}.env .env

                        docker compose --profile prod up -d --build
                        """
                    }

                    else if (branch == 'dev') {
                        sh """
                        cd /root/projects/${project}-dev

                        git fetch origin
                        git reset --hard origin/dev
                        git clean -fd

                        ln -sf /root/envs/${project}-dev.env .env

                        docker compose --profile dev up -d --build
                        """
                    }

                    else {
                        echo "Branch não suportada: ${branch}"
                    }
                }
            }
        }

    }
}
