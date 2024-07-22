FROM python:3.8-slim-buster

WORKDIR /src

COPY /analytics .

RUN pip install --upgrade pip &&\
    pip install -r requirements.txt

CMD python app.py