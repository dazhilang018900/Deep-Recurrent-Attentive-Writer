for p in ("Knet","ArgParse","GZip","AutoGrad","GZip","Compat", "Images", "ImageMagick")
    Pkg.installed(p) == nothing && Pkg.add(p)
end

using Knet
using ArgParse
using AutoGrad
using GZip
using Compat
using Images
using ImageMagick

function main(args)
    s = ArgParseSettings()
    @add_arg_table s begin
        ("--outdir"; default=nothing)
        ("--attention"; default="false")
    end

    global hasgpu = false
    atype = Array{Float32}
    if gpu()>=0
      atype = KnetArray{Float32}
      global hasgpu = true
    end

    isa(args, AbstractString) && (args=split(args))
    o = parse_args(args, s; as_symbols=true); println(o); flush(STDOUT)

    outdir = ""
    read_attn_mode = false
    write_attn_mode = false

    if o[:outdir] != nothing
        o[:outdir] = abspath(o[:outdir])
        outdir = o[:outdir]
        !isdir(o[:outdir]) && mkdir(o[:outdir])
    end
    if o[:attention] == "true"
      read_attn_mode = true
      write_attn_mode = true
    end

    A=28 #image width
    B=28 #image height
    img_size = B*A #canvas size
    enc_size = 256 #number of hidden units / output size in LSTM
    dec_size = 256
    read_n = 5 #read glimpse grid width/height
    write_n = 5 #write glimpse grid width/height
    z_size = 10 #QSampler output size
    T = 64 #MNIST generation sequence length
    batch_size = 100 #training minibatch size
    train_iters = 10000
    learning_rate = 1e-3 #learning rate for optimizer
    bt1 = 0.5

    w = initweights(read_attn_mode, atype, A, B, enc_size, read_n, write_n)
    parameters = initparams(w, learning_rate, bt1)

    (xtrnraw,ytrnraw,xtstraw,ytstraw)=loaddata()

    xtrn = convert(Array{Float32}, reshape(xtrnraw ./ 255, B*A, div(length(xtrnraw), img_size)))
    ytrnraw[ytrnraw.==0]=10;
    ytrn = convert(Array{Float32}, sparse(convert(Vector{Int},ytrnraw),1:length(ytrnraw),one(eltype(ytrnraw)),10,length(ytrnraw)))

    xtst = convert(Array{Float32}, reshape(xtstraw ./ 255, B*A, div(length(xtstraw), img_size)))
    ytstraw[ytstraw.==0]=10;
    ytst = convert(Array{Float32}, sparse(convert(Vector{Int},ytstraw),1:length(ytstraw),one(eltype(ytstraw)),10,length(ytstraw)))
    # seperate it into batches.

    dtrn = minibatch(xtrn, ytrn, batch_size)
    dtst = minibatch(xtst, ytst, batch_size)

    x = convert_if_gpu(atype, dtrn[1][1])
    cs = Any[]
    initialstate = [convert_if_gpu(atype, zeros(batch_size,enc_size)), convert_if_gpu(atype, zeros(batch_size,enc_size))]

    println("Epoch: ", 0, ", Loss: ", total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x, initialstate, outdir, cs, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n))
    random_numbers = Any[]
    for i in 1:100
      push!(random_numbers, [Int(round(rand()*28)), Int(round(rand()*28))])
    end

    for t in 1:T
        out = min(1,max(0,((cs[t])'+1)/2))
        png = makegrid(out, random_numbers)
        filename = @sprintf("%05d_%02d.png",0,t)

        save(joinpath(outdir,filename), png)
    end
    println("INFO: 10 images were generated at the directory ", outdir)

    for epoch = 1:10000
      indexfortrn = 1
      if rem(epoch,600) == 0
        indexfortrn = 1
      else
        indexfortrn = rem(epoch, 600)
      end
      indexfortst = 1
      if rem(epoch,100) == 0
        indexfortst = 1
      else
        indexfortst = rem(epoch, 100)
      end

            x1 = dtrn[indexfortrn][1]
            x2 = dtrn[600-indexfortrn+1][1]
            x3 = dtst[indexfortst][1]
            x4 = dtst[100-indexfortst+1][1]
            cs1 = Any[]
            cs2 = Any[]
            cs3 = Any[]
            cs4 = Any[]
            train(w, x1, parameters, batch_size, enc_size, dec_size, img_size, z_size, T, initialstate, outdir, cs1, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)

            if (rem(epoch, 100)==0)
              train_loss = total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x1, initialstate, outdir, cs1, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)
              total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x2, initialstate, outdir, cs2, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)

              test_loss = total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x3, initialstate, outdir, cs3, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)
              total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x4, initialstate, outdir, cs4, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)

              random_numbers1 = Any[]
              random_numbers2 = Any[]
              random_numbers3 = Any[]
              random_numbers4 = Any[]
              for i in 1:100
                push!(random_numbers1, [Int(round(rand()*28)), Int(round(rand()*28))])
                push!(random_numbers2, [Int(round(rand()*28)), Int(round(rand()*28))])
                push!(random_numbers3, [Int(round(rand()*28)), Int(round(rand()*28))])
                push!(random_numbers4, [Int(round(rand()*28)), Int(round(rand()*28))])
              end

              for t in 1:T
                  out1 = min(1,max(0,((cs1[t])'+1)/2))
                  png1 = makegrid(out1, random_numbers1)
                  out2 = min(1,max(0,((cs2[t])'+1)/2))
                  png2 = makegrid(out2, random_numbers2)
                  png = min(1, png1+png2)
                  filename = @sprintf("trn_%05d_%02d.png",epoch,t)
                  save(joinpath(outdir,filename), png)
              end

              for t in 1:T
                  out1 = min(1,max(0,((cs3[t])'+1)/2))
                  png1 = makegrid(out1, random_numbers3)
                  out2 = min(1,max(0,((cs4[t])'+1)/2))
                  png2 = makegrid(out2, random_numbers4)
                  png = min(1, png1+png2)
                  filename = @sprintf("tst_%05d_%02d.png",epoch,t)
                  save(joinpath(outdir,filename), png)
              end

              println("Epoch: ", epoch, ", TrnLoss: ", train_loss, ", TstLoss: ", test_loss)
              println("INFO: 128 images were generated at the directory ", outdir)
            end
    end
end

function initweights(read_attn_mode, atype, A, B, enc_size, read_n, write_n) #0.01
  weights=Dict()
  if (!read_attn_mode)
    weights = Dict([
    ("encoder_w", 0.05*randn(2*(A*B+enc_size), enc_size*4)),
    ("encoder_b", zeros(1,enc_size*4)),
    ("mu_w", 0.05*randn(enc_size,10)),
    ("mu_b", zeros(1,10)),
    ("sigma_w", 0.05*randn(enc_size,10)),
    ("sigma_b", zeros(1,10)),
    ("decoder_w", 0.05*randn(enc_size+10,enc_size*4)),
    ("decoder_b", zeros(1,enc_size*4)),
    ("write_w", 0.05*randn(enc_size,A*B)),
    ("write_b", zeros(1,A*B))
    ])
  else
    weights = Dict([
    ("read_w", 0.05*randn(enc_size,read_n)),
    ("read_b", zeros(1,read_n)),
    ("encoder_w", 0.05*randn(562,enc_size*4)),
    ("encoder_b", zeros(1, enc_size*4)),
    ("mu_w", 0.05*randn(enc_size,10)),
    ("mu_b", zeros(1,10)),
    ("sigma_w", 0.05*randn(enc_size,10)),
    ("sigma_b", zeros(1,10)),
    ("decoder_w", 0.05*randn(enc_size+10,enc_size*4)),
    ("decoder_b", zeros(1,enc_size*4)),
    ("writeW_w", 0.05*randn(enc_size,write_n*write_n)),
    ("writeW_b", zeros(1,write_n*write_n)),
    ("write_w", 0.05*randn(enc_size,write_n)),
    ("write_b", zeros(1,write_n)),
    ])
  end
  weightsKnet = Dict()
  for k in keys(weights)
    weightsKnet[k] = convert_if_gpu(atype, weights[k])
  end
  return weightsKnet
end

function initparams(w,lr,bt1)
   result = Dict()
   for k in keys(w)
     result[k] = Adam(;lr=lr, gclip=5, beta1=bt1)
   end
   return result
end

function minibatch(X, Y, bs) #pyplot
    #takes raw input (X) and gold labels (Y)
    #returns list of minibatches (x, y)
    X = X'
    Y = Y'
    data = Any[]
    for i=1:bs:size(X, 1)
	     bl = i + bs - 1 <= size(X, 1) ? i + bs - 1 : size(X, 1)
	     push!(data, (X[i:bl, :], Y[i:bl, :]))
    end
    return data
end

function linear(x, scope, weights) ##########todo
  #=
    affine transformation Wx+b
    assumes x.shape = (batch_size, num_features)
  =#
  w = weights[string(scope, "_w")]
  b = weights[string(scope, "_b")]
  return x*w.+b
end

function convert_if_gpu(atype, input)
  if hasgpu == true
    return convert(atype, input)
  else
    return input
  end
end

function filterbank(gx, gy, sigma2, delta, N, A, B, atype)
    grid_i = convert_if_gpu(atype, zeros(1, 5))    #grid_i = tf.reshape(tf.cast(tf.range(N), tf.Float32), [1, -1])
    for i in 1:N
      grid_i[1,i] = i-1
    end

    mu_x = gx .+ (grid_i - N / 2 - 0.5) .* delta # eq 19
    mu_y = gy .+ (grid_i - N / 2 - 0.5) .* delta # eq 20

    a = zeros(1, 1, A)
    b = zeros(1, 1, B)

    for i in 1:A
      a[1,1,i]=i-1
    end

    for i in 1:B
      b[1,1,i]=i-1
    end

    mu_x = reshape(mu_x, 100, 5, 1)
    mu_y = reshape(mu_y, 100, 5, 1)

    sigma2 = reshape(sigma2, 100, 1, 1) # sigma2 = tf.reshape(sigma2, [-1, 1, 1])

    mu_x = convert_if_gpu(Array{Float32}, mu_x)
    mu_y = convert_if_gpu(Array{Float32}, mu_y)
    sigma2 = convert_if_gpu(Array{Float32}, sigma2)

    Fxbroad = (a.-mu_x) ./ (2*sigma2)
    Fybroad = (b.-mu_y) ./ (2*sigma2)

    Fx = exp(-Fxbroad.*Fxbroad) # 2*sigma2?
    Fy = exp(-Fybroad.*Fybroad)
    # normalize, sum over A and B dims
    Fx=Fx./max(sum(Fx,3),1e-8) #dims: (100,5,28)
    Fy=Fy./max(sum(Fy,3),1e-8) #dims: (100,5,28)

    Fx = convert_if_gpu(atype, Fx)
    Fy = convert_if_gpu(atype, Fy)

return Fx,Fy
end

function attn_window(scope, h_dec, N, weights, A, B, atype)
    params = linear(h_dec, scope, weights) #dims: (100,5)
    gx_ = params[:,1]
    gy_ = params[:,2]
    log_sigma2 = params[:,3] #dims: (100,1)
    log_delta = params[:,4]
    log_gamma = params[:,5] #dims: (100,1)
    gx=(A+1)/2*(gx_+1)
    gy=(B+1)/2*(gy_+1)
    sigma2=exp(log_sigma2) #dims: (100,1)
    delta=(max(A,B)-1)/(N-1)*exp(log_delta) # batch x N
    Fx, Fy = filterbank(gx, gy, sigma2, delta, N, A, B, atype) #dims: (100,5,28)
return Fx, Fy, exp(log_gamma) #==============================================================================================================================================#
end

function read_no_attn(x, x_hat, h_dec_prev, read_n, weights, A, B, atype)
  return hcat(x, x_hat)
end

function read_attn(x, x_hat, h_dec_prev, read_n, weights, A, B, atype)
    Fx, Fy, gamma=attn_window("read", h_dec_prev, read_n, weights, A, B, atype)
    img=filter_img(x,Fx,Fy,gamma,read_n,A,B,atype) # batch x (read_n*read_n)
    img_hat=filter_img(x_hat,Fx,Fy,gamma,read_n,A,B,atype)
    return hcat(img, img_hat) # concat along feature axis
end

function filter_img(x,Fx,Fy,gamma,N,A,B,atype)
        Fxt=permutedims(Fx, [1,3,2]) #dims(100,28,5)
        img=reshape(x,100,28,28)
        Fxt=convert_if_gpu(Array{Float32}, Fxt)
        img=convert_if_gpu(Array{Float32}, img)
        Fy=convert_if_gpu(Array{Float32}, Fy)
        FxtArray = Any[]
        imgArray = Any[]
        FyArray = Any[]
        for i in 1:100
          push!(FxtArray, convert_if_gpu(atype, Fxt[i,:,:]))
          push!(imgArray, convert_if_gpu(atype, img[i,:,:]))
          push!(FyArray, convert_if_gpu(atype, Fy[i,:,:]))
        end


        temp1 = imgArray[1]*FxtArray[1]
        for i in 2:100
          temp = imgArray[i]*FxtArray[i]
          temp1 = vcat(temp1, temp)
        end
        temp = reshape(temp1, 28, 100, 5)
        temp = permutedims(temp, [2, 1, 3])

        temp = convert_if_gpu(Array{Float32}, temp)
        tempArray = Any[]
        for i in 1:100
          push!(tempArray, convert_if_gpu(atype, temp[i,:,:]))
        end

        glimpse1 = FyArray[1]*tempArray[1]
        for i in 2:100
          foo = FyArray[i]*tempArray[i]
          glimpse1 = vcat(glimpse1, foo)
        end
        glimpse = reshape(glimpse1, 5, 100, 5)
        glimpse = permutedims(glimpse, [2,1,3])
        glimpse=reshape(glimpse,100,25)
return glimpse.*reshape(gamma,100,1)
end

function encode(weights, state, input)
  return lstm(weights, "encode", state, input)
end

function sampleQ(h_enc, weights, noise)
  mu = linear(h_enc, "mu", weights)
  logsigma = linear(h_enc, "sigma", weights)
  sigma = exp(logsigma)
  return mu+sigma.*noise, mu, logsigma, sigma
end

function decode(weights, state, input)
  return lstm(weights, "decode", state, input)
end

function write_no_attn(h_dec, write_n, batch_size, weights, A, B, atype)
  return linear(h_dec, "write", weights)
end

function write_attn(h_dec, write_n, batch_size, weights, A, B, atype)
    w = linear(h_dec, "writeW", weights)
    N = write_n
    w = reshape(w, batch_size, N, N) #dims: (100,5,5)
    Fx, Fy, gamma = attn_window("write", h_dec, write_n, weights, A, B, atype)
    Fyt=permutedims(Fy, [1,3,2]) #dims: (100,28,5)

    w = convert_if_gpu(Array{Float32}, w)
    Fx = convert_if_gpu(Array{Float32}, Fx)
    Fyt = convert_if_gpu(Array{Float32}, Fyt)
    wArray = Any[]
    FxArray = Any[]
    FytArray = Any[]

    for i in 1:batch_size
      push!(wArray, convert_if_gpu(atype, w[1,:,:]))
      push!(FxArray, convert_if_gpu(atype, Fx[1,:,:]))
      push!(FytArray, convert_if_gpu(atype, Fyt[1,:,:]))
    end

    temp1 = wArray[1]*FxArray[1]
    for i in 2:batch_size
      foo = wArray[i]*FxArray[i]
      temp1 = vcat(temp1, foo)
    end
    temp = reshape(temp1, write_n, 100, A)
    temp = permutedims(temp, [2,1,3])
    temp = convert_if_gpu(Array{Float32}, temp)
    tempArray = Any[]
    for i in 1:batch_size
      push!(tempArray, convert_if_gpu(atype, temp[1,:,:]))
    end

    wr1 = FytArray[1]*tempArray[1]
    for i in 2:batch_size
      foo = FytArray[i]*tempArray[i]
      wr1 = vcat(wr1, foo)
    end
    wr = reshape(wr1, A, 100, B)
    wr = permutedims(wr, [2,1,3])
    wr=reshape(wr,batch_size,B*A)
return wr.*reshape(1 ./ gamma, 100, 1)
end

function binary_crossentropy(t,o)
    eps = 1e-8 # epsilon for numerical stability
    return -(t.*log(o+eps) + (1.0-t).*log(1.0-o+eps))
end

function total_loss(w, batch_size, enc_size, dec_size, img_size, z_size, T, x, initialstate, outdir, cs, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)
  if read_attn_mode
    readmethod = read_attn
  else
    readmethod = read_no_attn
  end

  if write_attn_mode
    writemethod = write_attn
  else
    writemethod = write_no_attn
  end

  mus = Any[]
  logsigmas = Any[]
  sigmas = Any[]

  h_dec_prev = convert_if_gpu(atype, zeros(batch_size, dec_size))
  enc_state = initialstate
  dec_state = initialstate
  noise = 0.05*convert_if_gpu(atype, randn(batch_size, z_size))
  x = convert_if_gpu(atype, x)
  for t in 1:T
    c_prev = 0
    if (t==1)
        c_prev = convert_if_gpu(atype, zeros(batch_size, img_size))
      else
        c_prev = cs[t-1]
      end
      x_hat=x-sigm(c_prev) # error image
      r = readmethod(x,x_hat,h_dec_prev, read_n, w, A, B, atype)
      h_enc, enc_state=encode(w, enc_state, hcat(r,h_dec_prev))
      z,mustemp,logsigmastemp,sigmastemp=sampleQ(h_enc, w, noise)
      push!(mus, mustemp)
      push!(logsigmas, logsigmastemp)
      push!(sigmas, sigmastemp)
      h_dec,dec_state=decode(w, dec_state,z)
      cstemp=c_prev+writemethod(h_dec, write_n, batch_size, w, A, B, atype) # store results
      push!(cs, cstemp)
      h_dec_prev=h_dec
  end
    x_recons=sigm(cs[end])
    Lx=sum(binary_crossentropy(x,x_recons),2)
    Lx=sum(Lx)/length(Lx)
    kl_terms=Any[]
    for t in 1:T
      mu2=mus[t].*mus[t]
      sigma2=sigmas[t].*sigmas[t]
      logsigma=logsigmas[t]
      push!(kl_terms, 0.5*sum((mu2+sigma2-2*logsigma),2)-z_size*.5)
    end
    KL=sum(kl_terms)
    Lz=sum(KL)/length(KL)
    cost=Lx+Lz
    return cost
end

lossgradient = grad(total_loss)

function train(w, x, parameters, batch_size, enc_size, dec_size, img_size, z_size, T, initialstate, outdir, cs, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)
      g = lossgradient(w, batch_size, enc_size, dec_size, img_size, z_size, T, x, initialstate, outdir, cs, read_attn_mode, write_attn_mode, atype, A, B, read_n, write_n)
      for i in keys(w)
          update!(w[i], g[i], parameters[i])
      end
end

function lstm(weights, mode, state, input)
  if (mode == "encode")
    weight = weights["encoder_w"]
    bias = weights["encoder_b"]
  elseif (mode == "decode")
    weight = weights["decoder_w"]
    bias = weights["decoder_b"]
  end
    cell,hidden = state
    h       = size(hidden,2)
    gates   = hcat(input,hidden) * weight .+ bias
    forget  = sigm(gates[:,1:h])
    ingate  = sigm(gates[:,1+h:2h])
    outgate = sigm(gates[:,1+2h:3h])
    change  = tanh(gates[:,1+3h:4h])
    cell    = cell .* forget + ingate .* change
    hidden  = outgate .* tanh(cell)
    return (hidden, [cell,hidden]) ##changed
end

function makegrid(y, random_numbers; gridsize=[10,10], scale=2.0, shape=(28,28))
    y = convert_if_gpu(Array{Float32}, y)
    y = reshape(y, shape..., size(y,2)) #newdims:(28,28,100)
    y = map(x->y[:,:,x]', [1:size(y,3)...]) #newdims: List of 100 (28,28)
    shp = map(x->Int(round(x*2)), shape) #shp = shape*scale
    y = map(x->Images.imresize(x,shape), y) #newdims: List of 100 (28,28)
    gridx, gridy = gridsize #gridx = num of grids at x axis
    outdims = (gridx*shp[1]+gridx+1,gridy*shp[2]+gridy+1) #outdims: (571,571)
    out = zeros(outdims...) #initially black
    for k = 1:gridx+1; out[(k-1)*(shp[1]+1)+1,:] = 1.0; end #lines
    for k = 1:gridy+1; out[:,(k-1)*(shp[2]+1)+1] = 1.0; end #lines

    x0 = y0 = 2
    for k = 1:length(y)
        x1 = x0+shape[1]-1
        y1 = y0+shape[2]-1
        out[(x0+random_numbers[k][1]):(x1+random_numbers[k][1]),(y0+random_numbers[k][2]):(y1+random_numbers[k][2])] = y[k]

        y0 = y1+30
        if k % gridy == 0
            x0 = x1+30
            y0 = 2
        else
            y0 = y1+30
        end
    end

    return convert(Array{Float32,2}, map(x->isnan(x)?0:x, out))
end

function loaddata()
	info("Loading MNIST...")
	xtrn = gzload("train-images-idx3-ubyte.gz")[17:end]
	xtst = gzload("t10k-images-idx3-ubyte.gz")[17:end]
	ytrn = gzload("train-labels-idx1-ubyte.gz")[9:end]
	ytst = gzload("t10k-labels-idx1-ubyte.gz")[9:end]
	return (xtrn, ytrn, xtst, ytst)
end

function gzload(file; path="$file", url="http://yann.lecun.com/exdb/mnist/$file")
	isfile(path) || download(url, path)
	f = gzopen(path)
	a = @compat read(f)
	close(f)
	return(a)
end

!isinteractive() && !isdefined(Core.Main, :load_only) && main(ARGS)
