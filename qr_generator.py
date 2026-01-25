import qrcode

# 1. A tua "Chave Mestra" (Tem de ser igual ao que vamos por no Flutter)
segredo = "DESLIGAR_WAKEUP_AGORA"

# 2. Configuração do QR Code
qr = qrcode.QRCode(
    version=1,
    # ERROR_CORRECT_H significa High (Alto). 
    # Permite que o código seja lido mesmo se 30% estiver sujo ou danificado.
    error_correction=qrcode.constants.ERROR_CORRECT_H,
    box_size=20, # Tamanho de cada "quadradinho" (quanto maior, maior a imagem final)
    border=4,    # Margem branca à volta (obrigatório para funcionar bem)
)

# 3. Adicionar os dados
qr.add_data(segredo)
qr.make(fit=True)

# 4. Criar a imagem (Preto no Branco)
img = qr.make_image(fill_color="black", back_color="white")

# 5. Guardar o ficheiro
nome_ficheiro = "qr.png"
img.save(nome_ficheiro)

print(f"Sucesso! O teu QR Code foi guardado como '{nome_ficheiro}'.")