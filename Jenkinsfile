pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                sh 'docker build -t scott-nginx-app ./app'
            }
        }

        stage('Test Container') {
            steps {
                sh '''
                    docker rm -f test-nginx 2>/dev/null || true

                    docker run -d \
                      --name test-nginx \
                      -p 8081:80 \
                      scott-nginx-app

                    sleep 5

                    curl -f http://localhost:8081/

                    docker rm -f test-nginx
                '''
            }
        }
    }

    post {
        always {
            sh 'docker rm -f test-nginx 2>/dev/null || true'
        }
    }
}